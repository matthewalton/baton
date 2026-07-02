import Foundation
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix

/// Localhost HTTP server exposing the MCP endpoint at POST /mcp.
public final class DeckServer {
    public static let defaultPort = 8321

    private let mcp: MCPHandler
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?

    public init(mcp: MCPHandler, port: Int = DeckServer.defaultPort) {
        self.mcp = mcp
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    public func start() throws {
        let mcp = self.mcp
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPHandler(mcp: mcp))
                }
            }
        channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
    }

    public func stop() {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
    }
}

private final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let mcp: MCPHandler
    private var head: HTTPRequestHead?
    private var body: ByteBuffer?

    init(mcp: MCPHandler) {
        self.mcp = mcp
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            self.head = head
            self.body = nil
        case var .body(chunk):
            if body == nil {
                body = chunk
            } else {
                body?.writeBuffer(&chunk)
            }
        case .end:
            guard let head else { return }
            let response = route(head: head, body: body)
            write(context: context, head: head, response: response)
            self.head = nil
            self.body = nil
        }
    }

    private func route(head: HTTPRequestHead, body: ByteBuffer?) -> MCPHandler.Response {
        // DNS-rebinding protection: browser-originated cross-site requests are refused.
        if let origin = head.headers.first(name: "Origin"),
           let host = URLComponents(string: origin)?.host,
           !["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) {
            return MCPHandler.Response(status: 403, body: Data(#"{"error":"forbidden origin"}"#.utf8))
        }

        let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri

        switch (head.method, path) {
        case (.POST, "/mcp"):
            var data = Data()
            if var body {
                data = body.readData(length: body.readableBytes) ?? Data()
            }
            return mcp.handlePost(body: data)
        case (.GET, "/mcp"), (.DELETE, "/mcp"):
            // No server-initiated stream and no session state.
            return MCPHandler.Response(status: 405, body: nil)
        case (.GET, "/health"):
            return MCPHandler.Response(status: 200, body: Data(#"{"ok":true,"app":"deck"}"#.utf8))
        default:
            return MCPHandler.Response(status: 404, body: Data(#"{"error":"not found"}"#.utf8))
        }
    }

    private func write(context: ChannelHandlerContext, head requestHead: HTTPRequestHead, response: MCPHandler.Response) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        let bodyData = response.body ?? Data()
        headers.add(name: "Content-Length", value: String(bodyData.count))
        if !requestHead.isKeepAlive {
            headers.add(name: "Connection", value: "close")
        }

        let status = HTTPResponseStatus(statusCode: response.status)
        let responseHead = HTTPResponseHead(version: requestHead.version, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        if !bodyData.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: bodyData.count)
            buffer.writeBytes(bodyData)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        let promise: EventLoopPromise<Void>? = requestHead.isKeepAlive ? nil : context.eventLoop.makePromise()
        if let promise {
            promise.futureResult.whenComplete { _ in context.close(promise: nil) }
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
