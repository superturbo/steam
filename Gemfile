source 'https://rubygems.org'

gemspec

group :development do
  # gem 'locomotivecms_common', github: 'locomotivecms/common', ref: '4d1bd56'
  gem 'locomotivecms_common', github: 'superturbo/common', ref: 'd31c20f'
  # gem 'duktape', path: '../tmp/duktape.rb'
  # gem 'duktape', github: 'judofyr/duktape.rb', ref: '20ef6a5'
  # gem 'duktape', github: 'did/duktape.rb', branch: 'any-fixnum'

  gem 'rake'

  gem 'puma',               '~> 8.0'
  gem 'haml',               '~> 6.4'

  gem 'rack', '~> 3.0'
  gem 'rack-mini-profiler', '~> 4.0'
  gem 'flamegraph'
  gem 'stackprof' # ruby 2.1+ only
  gem 'memory_profiler'
end

group :test do
  gem 'rspec',              '~> 3.13'
  gem 'json_spec',          '~> 1.1.5'
  gem 'i18n-spec',          '~> 0.6.0'

  gem 'timecop',            '~> 0.9.1'

  # gem 'pry-byebug',         '~> 3.3.0'

  gem 'rack-test',          '~> 2.2'

  gem 'simplecov',          '~> 0.22.0', require: false
end
