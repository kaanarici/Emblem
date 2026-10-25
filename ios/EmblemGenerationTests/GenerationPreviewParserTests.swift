import Foundation
@testable import EmblemCore
import Testing

struct GenerationPreviewParserTests {
    private func data(_ s:String)->Data {Data(s.utf8)}
    private func preview(_ revision:Int,_ attempt:Int,_ blocks:String="[]",id:String="page-preview")->Data {
        data("{\"type\":\"pagePreview\",\"id\":\"\(id)\",\"revision\":\(revision),\"attempt\":\(attempt),\"blocks\":\(blocks)}")
    }
    @Test func replacesClearsAndTracksRevisionAcrossCompositionAttemptsWithoutCanonicalCount() {
        var p=GenerationStream()
        let body=#"[{"type":"text","id":"same","body":"Growing","style":"body"}]"#
        guard case .pagePreview(1,1,let blocks,_)=p.consume(preview(1,1,body)) else { Issue.record("No preview");return }
        #expect(blocks.map(\.id)==["same"])
        guard case .pagePreview(2,2,let empty,_)=p.consume(preview(2,2)) else {Issue.record("Clear missing");return};#expect(empty.isEmpty)
        _=p.consume(preview(3,2,body))
        _=p.consume(data(#"{"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":[{"type":"text","id":"final","body":"Authoritative","style":"body"}]}"#))
        guard case .finished(persisted:true,_,_)=p.consume(data(#"{"type":"terminal","status":"completed","revision":1,"blockCount":1,"persisted":true}"#)) else {Issue.record("Preview polluted canonical receipt count/revision");return}
    }
    @Test func draftDistinguishesNamedNoneAndUnsaid() {
        let body=#"[{"type":"text","id":"a","body":"Done","style":"body"},{"type":"text","id":"b","body":"Writ","style":"body"}]"#
        func draft(_ field:String)->String?? {
            var p=GenerationStream()
            let raw=data("{\"type\":\"pagePreview\",\"id\":\"page-preview\",\"revision\":1,\"attempt\":1,\"blocks\":\(body)\(field)}")
            guard case .pagePreview(_,_,_,let draft)=p.consume(raw) else { return "unparsed" }
            return draft
        }
        #expect(draft(#","draft":"b""#) == .some("b"))
        #expect(draft(#","draft":null"#) == .some(nil))
        #expect(draft("") == .none)
    }
    @Test func everyMalformedControlFailsBeforeGenericBlockCounting() {
        let bad=[preview(1,1,id:"wrong"),preview(0,1),preview(1,0),preview(-1,1),preview(1,-1),preview(9_007_199_254_740_992,1),preview(1,9_007_199_254_740_992),
                 data(#"{"type":"pagePreview","id":"page-preview","revision":1.5,"attempt":1,"blocks":[]}"#),
                 data(#"{"type":"pagePreview","id":"page-preview","revision":1,"blocks":[]}"#),
                 data(#"{"type":"pagePreview","id":"page-preview","revision":1,"attempt":1,"blocks":{}}"#),
                 preview(1,1,#"[{"type":"text","id":"bad"}]"#)]
        for raw in bad {
            var p=GenerationStream();guard case .failed(let e)=p.consume(raw) else {Issue.record("Accepted malformed preview \(String(decoding:raw,as:UTF8.self))");continue};#expect(e.code=="invalid_stream")
        }
    }
    @Test func repeatedRegressedOrAttemptResetControlsCannotReplacePresentation() {
        for (revision,attempt) in [(7,2),(6,2),(8,1)] {
            var p=GenerationStream();_=p.consume(preview(7,2))
            guard case .failed=p.consume(preview(revision,attempt)) else {Issue.record("Accepted rollback of preview control");continue}
        }
    }
    @Test func previewOnlyCannotSatisfyCanonicalTerminalCountAndEOFIsFailure() {
        var p=GenerationStream();_=p.consume(preview(1,1,#"[{"type":"text","id":"draft","body":"Draft","style":"body"}]"#))
        guard case .failed=p.consume(data(#"{"type":"terminal","status":"completed","blockCount":1}"#)) else {Issue.record("Preview counted as canonical");return}
        p=GenerationStream();_=p.consume(preview(1,1));guard case .failed(let e)=p.endOfStream() else {Issue.record("EOF completed");return};#expect(e.code=="stream_cutoff")
    }
    @Test func previewAndSnapshotCountsRemainIndependent() {
        var p=GenerationStream();_=p.consume(preview(9,3));_=p.consume(data(#"{"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":[{"type":"future","id":"unknown"}]}"#))
        guard case .finished=p.consume(data(#"{"type":"terminal","status":"completed","revision":1,"blockCount":1}"#)) else {Issue.record("Snapshot count changed");return}
    }
    @Test func refusalClearsBeforeTerminalAndLatePreviewCannotResurrectIt() {
        var p=GenerationStream();_=p.consume(preview(1,1))
        guard case .clearPagePreview=p.consume(data(#"{"type":"error","code":"refused","message":"Refused","retryable":false}"#)) else {Issue.record("Refusal did not invalidate presentation immediately");return}
        guard case .clearPagePreview=p.consume(preview(2,1)) else {Issue.record("Late preview resurrected refused content");return}
        guard case .failed(let e)=p.consume(data(#"{"type":"terminal","status":"completed","blockCount":0}"#)) else {Issue.record("Late completed terminal won");return};#expect(e.code=="refused")
    }
    @Test func postTerminalPreviewIsIgnoredLikeAllLateEvents() {
        var p=GenerationStream();_=p.consume(data(#"{"type":"terminal","status":"completed","blockCount":0}"#));#expect(p.consume(preview(1,1))==nil)
    }
}
