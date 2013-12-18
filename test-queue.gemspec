spec = Gem::Specification.new do |s|
  s.name = 'test-queue'
  s.version = '0.1.3'
  s.summary = 'parallel test runner'

  s.homepage = "http://github.com/tmm1/test-queue"

  s.authors = ["Aman Gupta"]
  s.email = "ruby@tmm1.net"

  s.has_rdoc = false
  s.bindir = 'bin'
  s.executables << 'rspec-queue'
  s.executables << 'minitest-queue'
  s.add_runtime_dependency 'redis', '~> 3.0'
  s.add_development_dependency 'rspec', '~> 2.13'
  s.add_development_dependency 'minitest', '~> 4.7.3'
  s.add_development_dependency 'pry-remote'

  s.files = `git ls-files`.split("\n")
end
