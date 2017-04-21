Pod::Spec.new do |s|
  s.name             = 'AnyAPI'
  s.version          = '0.1.0'
  s.summary          = 'AnyAPI lets you easily interface with any HTTP API on the internet'

  s.description      = <<-DESC
AnyAPI lets you easily interface with any HTTP API on the internet! AnyAPI uses Alamofire and ObjectMapper under the hood
                       DESC

  s.homepage         = 'https://github.com/jpmcglone/AnyAPI'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'JP McGlone' => 'jp@trifl.co' }
  s.source           = { :git => 'https://github.com/jpmcglone/AnyAPI.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/jpmcglone'

  s.ios.deployment_target = '9.0'

  s.source_files = 'AnyAPI/Classes/**/*'
  
#  s.resource_bundles = {
#    'AnyAPI' => ['AnyAPI/Assets/*.png']
#  }

#  s.public_header_files = 'Pod/Classes/**/*.h'
  s.dependency 'Alamofire'
  s.dependency 'ObjectMapper'
  s.dependency 'AlamofireNetworkActivityIndicator'
  s.dependency 'AlamofireObjectMapper'
end
