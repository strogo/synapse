require 'synapse/service_watcher/base/base'
require 'synapse/service_watcher/zookeeper/zookeeper'
require 'synapse/atomic'

require 'zk'
require 'thread'

class Synapse::ServiceWatcher
  class ZookeeperPollWatcher < ZookeeperWatcher
    def initialize(opts, synapse, reconfigure_callback)
      super(opts, synapse, reconfigure_callback)

      @poll_interval = @discovery['polling_interval_sec'] || 60

      @should_exit = Synapse::AtomicValue.new(false)
      @thread = nil
    end

    def start
      log.info 'synapse: ZookeeperPollWatcher starting'

      zk_connect do
        # Perform an initial discover so that we have a config_for_generator before
        # start exits.
        discover

        @thread = Thread.new {
          log.info 'synapse: zookeeper polling thread started'

          last_run = Time.now

          until @should_exit.get
            now = Time.now
            elapsed = now - last_run

            if elapsed >= @poll_interval
              last_run = now
              discover
            end

            sleep 0.5
          end

          log.info 'synapse: zookeeper polling thread exiting normally'
        }
      end
    end

    def stop
      log.warn 'synapse: ZookeeperPollWatcher stopping'

      zk_teardown do
        # Signal to the thread that it should exit, and then wait for it to
        # exit.
        @should_exit.set(true)
      end
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "zookeeper poll watcher expects zookeeper_poll method" unless @discovery['method'] == 'zookeeper_poll'
      raise ArgumentError, "zookeeper poll watcher expects integer polling_interval_sec >= 0" if (
          @discovery.has_key?('polling_interval_sec') &&
          !(@discovery['polling_interval_sec'].is_a?(Numeric) &&
          @discovery['polling_interval_sec'] >= 0)
        )
      raise ArgumentError, "missing or invalid zookeeper host for service #{@name}" \
        unless @discovery['hosts']
      raise ArgumentError, "invalid zookeeper path for service #{@name}" \
        unless @discovery['path']
    end

    def discover
      log.info 'synapse: zookeeper polling discover called'
      statsd_increment('synapse.watcher.zookeeper_poll.discover')

      # passing {} disables setting watches
      super({})
    end
  end
end
