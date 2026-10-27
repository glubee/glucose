"""AI arranges fact IDs; only the backend renders trusted text and values."""
import asyncio
import json
import os
from decimal import Decimal
from typing import Literal

import openai
from openai import AsyncOpenAI
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

DAILY_IDS = frozenset({
    "coverage_percent", "readings_count", "average_glucose", "minimum_glucose",
    "maximum_glucose", "intake_records", "insulin_records",
})
WEEKLY_IDS = frozenset({
    "days_with_data", "sufficient_days", "low_coverage_days", "pending_days", "missing_days",
    "average_glucose", "episode_groups", "insulin_records", "above_range_after_treatment_count",
})
GLUCOSE_IDS = {"average_glucose", "minimum_glucose", "maximum_glucose"}
DAY_IDS = {"days_with_data", "sufficient_days", "low_coverage_days", "pending_days", "missing_days"}


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ReportFact(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    value: Decimal | None

    @field_validator("value", mode="before")
    @classmethod
    def numeric_only(cls, value):
        if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float, Decimal))):
            raise ValueError("fact value must be a JSON number or null")
        return value

    @model_validator(mode="after")
    def valid_value(self):
        if self.id not in DAILY_IDS | WEEKLY_IDS:
            raise ValueError("unknown fact")
        if self.value is None:
            return self
        if not self.value.is_finite() or self.value < 0 or self.value > 10_000_000:
            raise ValueError("invalid fact value")
        if self.id not in GLUCOSE_IDS | {"coverage_percent"} and self.value != self.value.to_integral_value():
            raise ValueError("count must be an integer")
        maximum = 7 if self.id in DAY_IDS else 96 if self.id == "readings_count" else 100 if self.id == "coverage_percent" else None
        if maximum is not None and self.value > maximum:
            raise ValueError("fact out of range")
        return self


class ReportNarrationRequest(StrictModel):
    kind: Literal["DAILY", "WEEKLY"]
    facts: list[ReportFact] = Field(min_length=1, max_length=9)

    @model_validator(mode="after")
    def complete_facts(self):
        expected = DAILY_IDS if self.kind == "DAILY" else WEEKLY_IDS
        ids = [fact.id for fact in self.facts]
        if len(ids) != len(set(ids)) or set(ids) != expected:
            raise ValueError("facts must exactly match the report kind")
        return self


class NarrativeParagraphPlan(StrictModel):
    fact_ids: list[str] = Field(min_length=1, max_length=9)
    style: Literal["PLAIN", "CONCISE"]


class NarrativePlan(StrictModel):
    paragraphs: list[NarrativeParagraphPlan] = Field(min_length=1, max_length=3)


class NarrationUsage(StrictModel):
    input_tokens: int = 0
    output_tokens: int = 0


class ReportNarrationResponse(NarrativePlan):
    model: str
    usage: NarrationUsage


class ReportNarrationFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def validate_plan(plan: NarrativePlan, request: ReportNarrationRequest) -> None:
    ids = [fact_id for paragraph in plan.paragraphs for fact_id in paragraph.fact_ids]
    if len(ids) != len(set(ids)) or set(ids) != {fact.id for fact in request.facts}:
        raise ValueError("unknown, missing or repeated fact reference")


class OpenAIReportNarrator:
    def __init__(self, *, client=None, model=None, timeout_seconds=6.0):
        self.client = client
        self.model = model or os.getenv("REPORT_MODEL") or os.getenv("FOOD_MODEL") or os.getenv("OPENAI_MODEL") or "gpt-6-luna"
        self.timeout_seconds = timeout_seconds

    async def narrate(self, request: ReportNarrationRequest) -> ReportNarrationResponse:
        try:
            if self.client is None:
                api_key = os.getenv("OPENAI_API_KEY")
                if not api_key:
                    raise ReportNarrationFailure("UPSTREAM_AI_ERROR")
                self.client = AsyncOpenAI(api_key=api_key, max_retries=0, timeout=self.timeout_seconds)
            # Deliberately omit values, availability, identity, dates and free text.
            prompt = json.dumps({"kind": request.kind, "fact_ids": [fact.id for fact in request.facts]})
            async with asyncio.timeout(self.timeout_seconds):
                response = await self.client.responses.parse(
                    model=self.model,
                    input=[
                        {"role": "system", "content": (
                            "일일/주간 기록 요약의 문단 순서와 표현 유형만 선택하세요. "
                            "입력 fact_ids를 모두 정확히 한 번씩 1~3개 문단에 배치하세요. "
                            "그래프 존재·읽힌 비율·집계 상태, 이미지 값 통계, 기록 건수 순서가 자연스럽습니다. "
                            "각 문단 style은 PLAIN 또는 CONCISE입니다. 자유 문장·수치·추론을 만들지 마세요."
                        )},
                        {"role": "user", "content": prompt},
                    ],
                    text_format=NarrativePlan, max_output_tokens=800, store=False,
                )
            # Revalidate even test doubles / modified SDK clients at this boundary.
            payload = response.output_parsed
            plan = NarrativePlan.model_validate(payload.model_dump() if isinstance(payload, BaseModel) else payload)
            validate_plan(plan, request)
            usage = getattr(response, "usage", None)
            return ReportNarrationResponse(
                paragraphs=plan.paragraphs, model=self.model,
                usage=NarrationUsage(input_tokens=getattr(usage, "input_tokens", 0) or 0,
                                     output_tokens=getattr(usage, "output_tokens", 0) or 0),
            )
        except (asyncio.TimeoutError, openai.APITimeoutError) as error:
            raise ReportNarrationFailure("TIMEOUT") from error
        except ReportNarrationFailure:
            raise
        except (openai.APIError, ValueError, TypeError, AttributeError) as error:
            # Never include provider responses or user facts in an error message.
            raise ReportNarrationFailure("UPSTREAM_AI_ERROR") from error
