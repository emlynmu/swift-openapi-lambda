import AWSLambdaRuntime
import OpenAPIRuntime

import AWSLambdaEvents

/// Specialization of LambdaHandler which runs an OpenAPILambda
public struct OpenAPILambdaHandler<L: OpenAPILambda>: LambdaHandler {

    /// the input type for this Lambda handler (received from the `OpenAPILambda`)
    public typealias Event = L.Event

    /// the output type for this Lambda handler (received from the `OpenAPILambda`)
    public typealias Output = L.Output

    /// Initialize `OpenAPILambdaHandler`.
    ///
    /// Create application, set it up and create `OpenAPILambda` from application and create responder
    /// - Parameters
    ///   - context: Lambda initialization context
    public init(context: LambdaInitializationContext) throws {
        self.router = TrieRouter()
        self.transport = LambdaOpenAPITransport(router: self.router)
        self.lambda = try .init(transport: self.transport)
    }

    /// The Lambda handling method.
    /// Concrete Lambda handlers implement this method to provide the Lambda functionality.
    ///
    /// - Parameters:
    ///     - event: Event of type `Event` representing the event or request.
    ///     - context: Runtime ``LambdaContext``.
    ///
    /// - Returns: A Lambda result ot type `Output`.
    public func handle(_ request: Event, context: LambdaContext) async throws -> Output {

        // convert Lambda event source to OpenAPILambdaRequest
        let request = try lambda.request(context: context, from: request)

        // route the request to find the handlers and extract the paramaters
        let (handler, parameters) = try await router.route(method: request.0.method, path: request.0.path!)

        // call the request handler (and extract the HTTPRequest and HTTPBody)
        let httpRequest = request.0
        let httpBody = HTTPBody(stringLiteral: request.1 ?? "")
        let response = try await handler(httpRequest, httpBody, ServerRequestMetadata(pathParameters: parameters))

        // transform the response to an OpenAPILambdaResponse
        let maxPayloadSize = 10 * 1024 * 1024  // APIGateway payload is 10M max
        let body: String? = try? await String(collecting: response.1 ?? "", upTo: maxPayloadSize)
        let lambdaResponse: OpenAPILambdaResponse = (response.0, body)

        // transform the OpenAPILambdaResponse to the Lambda Output
        return lambda.output(from: lambdaResponse)
    }

    let router: LambdaOpenAPIRouter
    let transport: LambdaOpenAPITransport
    let lambda: L
}
