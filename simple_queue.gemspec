# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'simple_queue/version'

Gem::Specification.new do |gem|
  gem.name          = "simple_queue"
  gem.version       = SimpleQueue::VERSION
  gem.authors       = ["Guillermo Iguaran"]
  gem.email         = ["guilleiguaran@gmail.com"]
  gem.description   = %q{Simple background jobs}
  gem.summary       = %q{Simple background jobs using Rubinius Actors}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency "rubinius-actor"
  gem.add_dependency "case"
  gem.add_dependency "redis"
end
