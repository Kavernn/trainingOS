import XCTest
@testable import TrainingOS

@MainActor final class ProgressionTransportTests: XCTestCase {
    var defaults: UserDefaults!
    var queue: UserDefaultsSyncQueue!
    var manager: SyncManager!
    var suite: String!
    let context = ProgressionContext(date:"2026-10-02",sessionType:"bonus",sessionName:"A")
    override func setUp() async throws {
        suite="progression-transport-\(UUID().uuidString)";defaults=UserDefaults(suiteName:suite)!
        queue=UserDefaultsSyncQueue(defaults:defaults);manager=SyncManager(queue:queue);manager.isOnlineProvider={true}
    }
    override func tearDown() async throws { manager.urlSession.invalidateAndCancel();defaults.removePersistentDomain(forName:suite) }
    func request() -> ProgressionApplyRequest {
        .init(context:context,exercise:"X",programID:"fixture",weight:105,scheme:"4x12",expectedWeight:100,expectedScheme:"3x12")
    }
    func response(_ req: URLRequest, _ status:Int, _ body:String) -> (Data,URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url:req.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
    }
    func testFetchBonusExactContextAndHTTPFailure() async {
        let outcome=await APIService.shared.fetchProgressionSuggestions(context:context) { req in
            let items=URLComponents(url:req.url!,resolvingAgainstBaseURL:false)!.queryItems!
            XCTAssertEqual(items.first{$0.name=="session_type"}?.value,"bonus")
            XCTAssertEqual(items.first{$0.name=="date"}?.value,"2026-10-02")
            XCTAssertEqual(req.timeoutInterval,15)
            return self.response(req,401,"{}")
        }
        if case .failed(.http(401)) = outcome {} else {XCTFail()}
    }
    func testFetchNetworkCancellationAndDecode() async {
        let offline=await APIService.shared.fetchProgressionSuggestions(context:context){_ in throw URLError(.notConnectedToInternet)}
        if case .failed(.network) = offline {} else {XCTFail()}
        let cancelled=await APIService.shared.fetchProgressionSuggestions(context:context){_ in throw CancellationError()}
        if case .failed(.cancelled) = cancelled {} else {XCTFail()}
        let bad=await APIService.shared.fetchProgressionSuggestions(context:context){ self.response($0,200,"invalid") }
        if case .failed(.decoding) = bad {} else {XCTFail()}
    }
    func testApplyConfirmedOnlyOnValidACK() async {
        let outcome=await APIService.shared.applyProgression(request(),manager:manager){ req in
            let payload=try JSONSerialization.jsonObject(with:req.httpBody!) as! [String:Any]
            XCTAssertEqual(payload["expected_current_weight"] as? Double,100)
            return self.response(req,200,#"{"success":true,"current_weight":105,"current_scheme":"4x12"}"#)
        }
        if case .confirmed = outcome {} else {XCTFail()}
    }
    func testApplyQueuedAndDuplicateUsesSameBytes() async {
        manager.isOnlineProvider={false}
        let req=request()
        let first=await APIService.shared.applyProgression(req,manager:manager)
        let second=await APIService.shared.applyProgression(req,manager:manager)
        XCTAssertEqual(first,.queued);XCTAssertEqual(second,.queued)
        XCTAssertEqual(queue.load().count,1)
        XCTAssertEqual(queue.load().first?.payloadData,try JSONSerialization.data(withJSONObject:req.payload,options:[.sortedKeys]))
    }
    func testApplyServiceUnavailableFailsWithoutAutomaticRetry() async {
        let req=request()
        let result=await APIService.shared.applyProgression(req,manager:manager){
            self.response($0,503,#"{"success":false,"error":"Progression non confirmée"}"#)
        }
        if case .failed = result {} else {XCTFail("503 must fail, never queue")}
        if case .uncertain = manager.status(for:.init(rawValue:req.operationIdentity)) {} else {XCTFail()}
    }
    func testApplyConflict() async {
        let result=await APIService.shared.applyProgression(request(),manager:manager){ self.response($0,409,"{}") }
        XCTAssertEqual(result,.conflict)
    }
    func testInvalidACKIsUncertainNotConfirmed() async {
        let req=request()
        let result=await APIService.shared.applyProgression(req,manager:manager){self.response($0,200,#"{"success":false}"#)}
        if case .failed = result {} else {XCTFail()}
        if case .uncertain = manager.status(for:.init(rawValue:req.operationIdentity)) {} else {XCTFail()}
    }
    func testReplayRequiresBusinessACK() async throws {
        manager.isOnlineProvider={false};let req=request()
        _=await APIService.shared.applyProgression(req,manager:manager)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ProgressionURLProtocol.self]
        manager.urlSession=URLSession(configuration:config)
        ProgressionURLProtocol.body=Data(#"{"success":true,"current_weight":105,"current_scheme":"4x12"}"#.utf8)
        manager.isOnlineProvider={true};await manager.flushQueue()
        if case .delivered = manager.status(for:.init(rawValue:req.operationIdentity)) {} else {XCTFail()}
    }
    func testReplayInvalidACKIsNotDelivered() async throws {
        manager.isOnlineProvider={false};let req=request();_=await APIService.shared.applyProgression(req,manager:manager)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ProgressionURLProtocol.self]
        manager.urlSession=URLSession(configuration:config);ProgressionURLProtocol.body=Data("invalid".utf8)
        manager.isOnlineProvider={true};await manager.flushQueue()
        if case .uncertain = manager.status(for:.init(rawValue:req.operationIdentity)) {} else {XCTFail()}
    }
}
private final class ProgressionURLProtocol: URLProtocol {
    static var body=Data()
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
