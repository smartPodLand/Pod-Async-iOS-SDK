
Pod::Spec.new do |s|

  s.name         = "Fanap-Pod-Async-SDK"
  s.version      = "0.2.3"
  s.summary      = "Fanap's POD Async Service (DIRANA) - iOS SDK"
  s.description  = "This Package will use to connect the client to the Fanap's async service (DIRANA), and it will live the connection (with socket) to send and recieve messages..."
  s.homepage     = "https://github.com/smartPodLand/Pod-Async-iOS-SDK"
  s.license      = "MIT"
  s.author       = { "Mahyar" => "mahyar.zhiani@icloud.com" }
  s.platform     = :ios, "8.0"
  s.source       = { :git => "https://github.com/smartPodLand/Pod-Async-iOS-SDK.git", :tag => s.version }
  s.source_files = "Async/**/*.{h,m, swift}"
  s.frameworks = "Foundation"

  s.dependency "Starscream"
  s.dependency "SwiftyJSON"
  s.dependency "SwiftyBeaver"

end
