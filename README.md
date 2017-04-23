![AnyAPI: Easily interface with any API]()

[![Build Status](https://travis-ci.org/jpmcglone/AnyAPI.svg?branch=master)](https://travis-ci.org/jpmcglone/AnyAPI)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/AnyAPI.svg)](https://img.shields.io/cocoapods/v/AnyAPI.svg)
[![Carthage Compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Platform](https://img.shields.io/cocoapods/p/AnyAPI.svg?style=flat)](http://cocoadocs.org/docsets/AnyAPI)
[![Twitter](https://img.shields.io/badge/twitter-@jpmcglone-blue.svg?style=flat)](http://twitter.com/jpmcglone)
[![Gitter](https://badges.gitter.im/jpmcglone/AnyAPI.svg)](https://gitter.im/jpmcglone/AnyAPI?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

AnyAPI lets you easily interface with any HTTP JSON API.

- [Installation](#installation)
- [Requirements](#requirements)
- [Communication](#communication)
- [Usage](#usage)
- [Credits](#credits)
- [Donation](#donation)
- [License](#license)

## Requirements

- iOS 9.0+ 
- Xcode 8.1+
- Swift 3.0+

## Communication

- If you **need help**, use [Stack Overflow](http://stackoverflow.com/questions/tagged/anyapi). (Tag 'AnyAPI')
- If you'd like to **ask a general question**, use [Stack Overflow](http://stackoverflow.com/questions/tagged/anyapi).
- If you **found a bug**, open an issue.
- If you **have a feature request**, open an issue.
- If you **want to contribute**, submit a pull request.

## Installation

### CocoaPods

[CocoaPods](http://cocoapods.org) is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

> CocoaPods 1.1.0+ is required to build AnyAPI 1.0.0+.

To integrate AnyAPI into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '9.0'
use_frameworks!

target '<Your Target Name>' do
    pod 'AnyAPI', '~> 4.4'
end
```

Then, run the following command:

```bash
$ pod install
```

### Carthage

#### Support coming soon

[Carthage](https://github.com/Carthage/Carthage) is a decentralized dependency manager that builds your dependencies and provides you with binary frameworks.

You can install Carthage with [Homebrew](http://brew.sh/) using the following command:

```bash
$ brew update
$ brew install carthage
```

To integrate AnyAPI into your Xcode project using Carthage, specify it in your `Cartfile`:

```ogdl
github "jpmcglone/AnyAPI" ~> 4.4
```

Run `carthage update` to build the framework and drag the built `AnyAPI.framework` into your Xcode project.

### Swift Package Manager

#### Support coming soon

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler. It is in early development, but AnyAPI does support its use on supported platforms. 

Once you have your Swift package set up, adding AnyAPI as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .Package(url: "https://github.com/AnyAPI/AnyAPI.git", majorVersion: 4)
]
```

## Usage

### Making a Request

```swift
import AnyAPI

let MyAPI = AnyAPI()
MyAPI.baseURL = URL(string: "https://myapi.com/api")
MyAPI.baseParameters = ["api_key": "xxx"]

MyAPI.request(method: .get, uri: "posts", parameters = ["sort": "time"])
```

### Response Handling

Handling the `Response` of a `Request` made in AnyAPI involves chaining a response handler onto the `Request`.
Since this library is built on top of Alamofire, it works with any Alamofire `.response` method

```swift
MyAPI.request(method: .get, uri: "posts").responseJSON { response in
    print(response.request)  // original URL request
    print(response.response) // HTTP URL response
    print(response.data)     // server data
    print(response.result)   // result of response serialization

    if let JSON = response.result.value {
        print("JSON: \(JSON)")
    }
}
```

AnyAPI also uses `AlamofireObjectMapper` and allows you to serialize responses automagically to `ObjectMapper`'s `Mappable` objects

```swift
MyAPI.request(method: .get, uri: "posts").responseArray { DataResponse<[Post]> response in
  if let posts = response.result.value { 
    // serialized posts
  }
}
```

Alamofire contains five different response handlers by default including:

```swift
// Response Handler - Unserialized Response
func response(
    queue: DispatchQueue?,
    completionHandler: @escaping (DefaultDataResponse) -> Void)
    -> Self

// Response Data Handler - Serialized into Data
func responseData(
    queue: DispatchQueue?,
    completionHandler: @escaping (DataResponse<Data>) -> Void)
    -> Self

// Response String Handler - Serialized into String
func responseString(
    queue: DispatchQueue?,
    encoding: String.Encoding?,
    completionHandler: @escaping (DataResponse<String>) -> Void)
    -> Self

// Response JSON Handler - Serialized into Any
func responseJSON(
    queue: DispatchQueue?,
    completionHandler: @escaping (DataResponse<Any>) -> Void)
    -> Self

// Response PropertyList (plist) Handler - Serialized into Any
func responsePropertyList(
    queue: DispatchQueue?,
    completionHandler: @escaping (DataResponse<Any>) -> Void))
    -> Self
```

ObjectMapperAlamofire contains two response handlers by default including:

```swift 
// Response Object Handler - Serialized into Mappable
func responseObject(
   queue: DispatchQueue?,
   completionHandler: @escaping (DataResponse<Mappable>) -> Void))

// Response Array Handler - Serialized into [Mappable]
func responseArray(
   queue: DispatchQueue?,
   completionHandler: @escaping (DataResponse<[Mappable]>) -> Void))
```

None of the response handlers perform any validation of the `HTTPURLResponse` it gets back from the server.

> For example, response status codes in the `400..<499` and `500..<599` ranges do NOT automatically trigger an `Error`. Alamofire uses [Response Validation](#response-validation) method chaining to achieve this.

#### Response Handler

The `response` handler does NOT evaluate any of the response data. It merely forwards on all information directly from the URL session delegate. It is the Alamofire equivalent of using `cURL` to execute a `Request`.

```swift
MyAPI.request(method: .get, uri: "posts").response { response in
    print("Request: \(response.request)")
    print("Response: \(response.response)")
    print("Error: \(response.error)")

    if let data = response.data, let utf8Text = String(data: data, encoding: .utf8) {
    	print("Data: \(utf8Text)")
    }
}
```

> We strongly encourage you to leverage the `responseObject` and `responseArray` methods to take advantage of AnyAPI to its fullest

For more on how to use the `Alamofire` portions of `AnyAPI`, please read [Alamofire's README](https://github.com/Alamofire/Alamofire/blob/master/README.md)

## Credits

AnyAPI is owned and maintained by the [@jpmcglone](https://www.github.com/jpmcglone). You can follow him on Twitter at [@jpmcglone](https://twitter.com/jpmcglone) for project updates and releases.


## Donations

#### Coming soon

## License

AnyAPI is released under the MIT license. [See LICENSE](https://github.com/jpmcglone/AnyAPI/blob/master/LICENSE) for details.
