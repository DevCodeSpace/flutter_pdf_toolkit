Pod::Spec.new do |s|
  s.name             = 'flutter_pdf_toolkit'
  s.version          = '0.0.1'
  s.summary          = 'Flutter native PDF viewer'
  s.description      = <<-DESC
Native PDF viewer plugin for Flutter.
  DESC
  s.homepage         = 'https://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Codex' => 'codex@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
