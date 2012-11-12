# SimpleQueue

SimpleQueue is a simple background system for Ruby

## Installation

Add this line to your application's Gemfile:

    gem 'simple_queue'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install simple_queue

## Usage

### Queue

You must set a queue in your application to save jobs:

```ruby
JobQueue = SimpleQueue::Queue.new(:jobs)
```

### Jobs

The jobs should be Ruby objects that respond to `#run` method (without
arguments), there is a simple example:

```ruby
class ComputationJob < Struct.new(:seconds)
  def run
    sleep @seconds
  end
end
```

Then you can insert jobs in the queue:

```ruby
JobQueue.push(ComputationJob.new(10))
```

### Consumers
One or multiple workers should be started to consume jobs, this can be
done for example in a rake task:

```ruby
# jobs.rake
namespace :jobs do
  desc "Run worker for jobs"
  task :work => :environment do
    consumer = SimpleQueue::Consumer.new(:jobs)
    consumer.start
  end
end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
