//
//  GraphBatchUploader.swift
//  glucose
//
//  리브레 일일 그래프 여러 장을 한 번에 올린다. 한 장 = 하루, 날짜는 서버가 이미지에서 읽는다.
//  한 번에 3장씩 올리고(서버 분석 작업은 차례로 처리된다), 실패한 장은 따로 다시 시도할 수 있다.
//

import Foundation
import UIKit

@MainActor
@Observable
final class GraphBatchItem: Identifiable {
    let id = UUID()
    let thumbnail: UIImage?
    let data: Data?
    let contentType: String
    let uploader = GraphUploadViewModel()

    init(originalData: Data) {
        let prepared = ImageResizer.prepareGraphForUpload(originalData: originalData)
        data = prepared?.data
        contentType = prepared?.contentType ?? "image/jpeg"
        thumbnail = UIImage(data: originalData)?.preparingThumbnail(of: CGSize(width: 120, height: 200))
    }

    var state: GraphUploadState {
        data == nil ? .failed("이미지를 불러오지 못했어요. 다른 이미지를 골라주세요.") : uploader.state
    }

    var isFinished: Bool {
        switch state {
        case .done, .failed: true
        default: false
        }
    }

    /// 날짜순 정렬용(아직 날짜를 모르면 nil)
    var resultDate: String? {
        if case .done(let date, _) = state { return date }
        return nil
    }
}

@MainActor
@Observable
final class GraphBatchUploader {
    private(set) var items: [GraphBatchItem] = []
    private(set) var isRunning = false
    private static let concurrency = 3

    var doneCount: Int { items.filter { $0.resultDate != nil }.count }
    var failedCount: Int { items.filter { if case .failed = $0.state { true } else { false } }.count }
    var finishedCount: Int { items.filter(\.isFinished).count }

    /// 같은 날짜로 읽힌 장이 여러 개면 나중에 끝난 것으로 덮어써진다
    var duplicateDates: [String] {
        let dates = items.compactMap(\.resultDate)
        return Set(dates.filter { date in dates.filter { $0 == date }.count > 1 }).sorted()
    }

    func add(originalData: [Data]) {
        items += originalData.map { GraphBatchItem(originalData: $0) }
    }

    func clear() {
        guard !isRunning else { return }
        items = []
    }

    /// 아직 안 올렸거나 실패한 장을 올린다
    func run() async {
        guard !isRunning else { return }
        let queue = items.filter { item in
            guard item.data != nil else { return false }
            switch item.uploader.state {
            case .idle, .failed: return true
            default: return false
            }
        }
        guard !queue.isEmpty else { return }
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isRunning = false
            UIApplication.shared.isIdleTimerDisabled = false
        }

        var next = 0
        await withTaskGroup(of: Void.self) { group in
            func startNext() {
                guard next < queue.count else { return }
                let item = queue[next]
                next += 1
                group.addTask { @MainActor in
                    guard let data = item.data else { return }
                    await item.uploader.upload(imageData: data, contentType: item.contentType)
                }
            }
            for _ in 0..<Self.concurrency { startNext() }
            while await group.next() != nil { startNext() }
        }
    }
}
