# HTTPError Usage Examples

Now that AnyAPI has been enhanced with proper HTTP error handling, here are practical examples of how to use the new `HTTPError` structure to extract response bodies from failed requests.

## Basic Usage

```swift
import AnyAPI

struct LoginEndpoint: Endpoint {
    struct Response: Codable {
        let token: String
        let user: User
    }
    
    let email: String
    let password: String
    
    var path: String { "auth/login" }
    var method: HTTPMethod { .post }
    
    func asParameters() throws -> Parameters {
        return [
            "email": email,
            "password": password
        ]
    }
}

// Usage with enhanced error handling
let client = APIClient(baseURL: URL(string: "https://api.example.com")!, 
                       defaultHeaders: { [:] })

do {
    let response = try await client(LoginEndpoint(email: "user@example.com", password: "wrong"))
        .run
    print("Login successful: \(response.token)")
} catch let httpError as HTTPError {
    // Now you can access the full error response!
    print("HTTP Status: \(httpError.statusCode)")
    
    if let errorBody = httpError.responseBody {
        print("Error Response Body: \(errorBody)")
    }
    
    // Extract error message automatically from common formats
    if let errorMessage = httpError.extractErrorMessage() {
        print("Error Message: \(errorMessage)")
    }
    
    // Check specific error types
    if httpError.isUnauthorized {
        print("Authentication failed")
    } else if httpError.isServerError {
        print("Server error occurred")
    }
} catch {
    print("Network error: \(error)")
}
```

## Decoding Structured Error Responses

```swift
// Define your API's error response structure
struct APIErrorResponse: Codable {
    let error: String
    let code: String
    let details: [String]?
    let timestamp: String
}

do {
    let response = try await client(someEndpoint).run
} catch let httpError as HTTPError {
    // Try to decode the structured error response
    do {
        let errorResponse = try httpError.decodeError(as: APIErrorResponse.self)
        print("API Error: \(errorResponse.error)")
        print("Error Code: \(errorResponse.code)")
        
        if let details = errorResponse.details {
            print("Details: \(details.joined(separator: ", "))")
        }
    } catch {
        // Fall back to simple error message extraction
        let message = httpError.extractErrorMessage() ?? "Unknown error"
        print("Error: \(message)")
    }
}
```

## Handling Different Error Scenarios

```swift
do {
    let response = try await client(endpoint).run
    // Handle success
} catch let httpError as HTTPError {
    switch httpError.statusCode {
    case 400:
        // Bad Request - usually validation errors
        if let validationErrors = try? httpError.decodeError(as: ValidationErrorResponse.self) {
            handleValidationErrors(validationErrors)
        }
        
    case 401:
        // Unauthorized - token expired or invalid
        await refreshTokenAndRetry()
        
    case 403:
        // Forbidden - user doesn't have permission
        showPermissionDeniedAlert()
        
    case 404:
        // Not Found
        showNotFoundError()
        
    case 429:
        // Rate Limited
        if let retryAfter = httpError.response?.value(forHTTPHeaderField: "Retry-After") {
            scheduleRetryAfter(seconds: Int(retryAfter) ?? 60)
        }
        
    case 500...599:
        // Server Error
        reportServerError(httpError)
        
    default:
        // Other HTTP errors
        showGenericError(httpError.extractErrorMessage() ?? "Request failed")
    }
} catch {
    // Network errors, timeouts, etc.
    handleNetworkError(error)
}
```

## Error Message Extraction Examples

The `extractErrorMessage()` method automatically handles common API error response formats:

```swift
// These JSON formats are automatically parsed:

// Format 1: {"error": "Invalid credentials"}
// Format 2: {"message": "User not found"}  
// Format 3: {"detail": "Validation failed"}
// Format 4: {"description": "Server unavailable"}
// Format 5: {"error": {"message": "Nested error"}}

// Example with different response formats
catch let httpError as HTTPError {
    if let message = httpError.extractErrorMessage() {
        // Will extract the appropriate error message from any of the above formats
        displayError(message)
    } else {
        // Fallback to raw response body
        displayError(httpError.responseBody ?? "Unknown error occurred")
    }
}
```

## Custom Error Handling with Response Headers

```swift
catch let httpError as HTTPError {
    // Access full HTTP response for custom handling
    if let response = httpError.response {
        // Check custom headers
        if let errorCode = response.value(forHTTPHeaderField: "X-Error-Code") {
            handleCustomError(code: errorCode)
        }
        
        // Check content type for special handling
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("application/problem+json") {
            // Handle RFC 7807 Problem Details
            handleProblemDetails(httpError.data)
        }
    }
    
    // Always have the raw data available
    if let data = httpError.data {
        logErrorToAnalytics(statusCode: httpError.statusCode, 
                           responseData: data)
    }
}
```

## Backward Compatibility

If you're migrating from the old error handling, the legacy `AnyAPIError` still works:

```swift
catch let error as AnyAPIError {
    switch error {
    case .http(let httpError):
        // New HTTPError wrapped in legacy enum
        handleHTTPError(httpError)
    case .unauthorized:
        // Legacy handling still works
        handleUnauthorized()
    case .server(let message):
        // Legacy server error
        displayError(message)
    case .decoding(let decodingError):
        // Decoding errors
        handleDecodingError(decodingError)
    case .custom(let message):
        // Custom errors
        displayError(message)
    }
}
```

## Key Benefits

1. **Response Body Access**: You can now access the full response body even for failed requests
2. **Structured Error Handling**: Decode error responses into your own types
3. **Automatic Message Extraction**: Common error message formats are parsed automatically  
4. **Rich Error Information**: Access status codes, headers, and raw data
5. **Backward Compatible**: Existing error handling code continues to work
6. **Type Safety**: Strong typing for all error information

This enhanced error handling makes it much easier to provide meaningful error messages to users and implement robust error recovery strategies in your applications. 