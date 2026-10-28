package com.glucoselog.glucose;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

class GraphParserVersionTest {
    @ParameterizedTest
    @CsvSource({"1.0.0,false", "1.1.3,false", "1.1.4,true", "1.1.5,true", "1.10.0,true", "2.0.0,true"})
    void versions_are_compared_numerically(String version, boolean supported) {
        assertThat(GraphParserVersion.isSupported(version)).isEqualTo(supported);
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"test", "1.1", "1.1.5-unknown", "999999999999999.1.0"})
    void unknown_versions_are_not_trusted(String version) {
        assertThat(GraphParserVersion.isSupported(version)).isFalse();
    }
}
