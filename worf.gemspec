Gem::Specification.new do |s|
  s.name        = "worf"
  s.version     = "1.0.0"
  s.summary     = "Parse DWARF information in Ruby"
  s.description = "Tired of parsing DWARF information in C? Now you can parse DWARF information in Ruby!"
  s.authors     = ["Aaron Patterson"]
  s.email       = "tenderlove@ruby-lang.org"
  s.files       = `git ls-files -z`.split("\x0")
  s.test_files  = s.files.grep(%r{^test/})
  s.homepage    = "https://github.com/tenderlove/worf"
  s.license     = "Apache-2.0"
  s.add_development_dependency 'minitest', '~> 5.14'
  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'odinflex', '~> 1.0'
end
