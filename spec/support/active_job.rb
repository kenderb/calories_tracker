RSpec.configure do |config|
  # Jobs are asserted on explicitly; nothing runs inline by accident.
  config.before { ActiveJob::Base.queue_adapter = :test }
end
