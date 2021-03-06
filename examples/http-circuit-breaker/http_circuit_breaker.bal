import ballerina/http;
import ballerina/log;
import ballerina/lang.runtime;

// The circuit breaker looks for errors across a rolling time window.
// After the circuit is broken, it does not send requests to
// the backend until the `resetTime`.
http:Client backendClientEP = check new ("http://localhost:8080", {
            // Configuration options that control the behavior of the circuit
            // breaker.
            circuitBreaker: {
                // Failure calculation window. This is how long the circuit
                // breaker keeps the statistics for the operations.
                rollingWindow: {

                    // Time period in milliseconds for which the failure
                    // threshold is calculated.
                    timeWindow: 10,

                    // The granularity (in milliseconds) at which the time
                    // window slides. The `RollingWindow` is divided into
                    // buckets and slides by these increments.
                    bucketSize: 2,

                    // Minimum number of requests in the `RollingWindow` that
                    // will trip the circuit.
                    requestVolumeThreshold: 0

                },
                // The threshold for request failures.
                // When this threshold exceeds, the circuit trips. This is the
                // ratio between failures and total requests. The ratio is
                // calculated using the requests received within the given
                // rolling window.
                failureThreshold: 0.2,

                // The time period (in milliseconds) to wait before attempting to
                // make another request to the upstream service.
                resetTime: 10,

                // HTTP response status codes that are considered as failures
                statusCodes: [400, 404, 500]

            },
            timeout: 2
        }
    );

// Create an HTTP service bound to the endpoint (circuitBreakerEP).
service /cb on new http:Listener(9090) {

    resource function get .(http:Caller caller, http:Request request) {
        var backendResponse = backendClientEP->forward("/hello", request);
        // If the `backendResponse` is an `http:Response`, it is sent back to
        // the client. If `backendResponse` is an `http:ClientError`, an
        // internal server error is returned to the client.
        if (backendResponse is http:Response) {
            var responseToCaller = caller->respond(<@untainted>backendResponse);
            if (responseToCaller is http:ListenerError) {
                log:printError("Error sending response",
                                'error = responseToCaller);
            }
        } else {
            http:Response response = new;
            response.statusCode = http:STATUS_INTERNAL_SERVER_ERROR;
            response.setPayload((<@untainted error>backendResponse).message());
            var responseToCaller = caller->respond(response);
            if (responseToCaller is http:ListenerError) {
                log:printError("Error sending response",
                                'error = responseToCaller);
            }
        }

    }
}

int counter = 1;

// This sample service is used to mock connection timeouts and service outages.
// This should run separately from the `circuitBreakerDemo` service.
service /hello on new http:Listener(8080) {

    resource function get .(http:Caller caller, http:Request req) {
        if (counter % 5 == 0) {
            // Delay the response by 5000 milliseconds to
            // mimic the network level delays.
            runtime:sleep(5);

            var result = caller->respond("Hello World!!!");
            handleRespondResult(result);
        } else if (counter % 5 == 3) {
            http:Response res = new;
            res.statusCode = 500;
            res.setPayload(
                "Internal error occurred while processing the request.");
            var result = caller->respond(res);
            handleRespondResult(result);
        } else {
            var result = caller->respond("Hello World!!!");
            handleRespondResult(result);
        }
        counter = counter + 1;
    }
}

function handleRespondResult(error? result) {
    if (result is http:ListenerError) {
        log:printError("Error sending response from mock service",
                        'error = result);
    }
}
