# frozen_string_literal: true

module Certstream
  module Jobs
    class RetryUnresolvableDomainsJob
      def initialize(max_retries)
        @max_retries = max_retries
      end

      def perform
        # First, clean up domains older than 3 days
        Core.container.database.cleanup_old_unresolvable_domains

        # The database.unresolvable_domains method only return domains older than 1 day
        domains = Core.container.database.unresolvable_domains
        Core.container.logger.info("Found #{domains.size} unresolvable domains to retry")

        domains.each do |domain|
          Core.container.logger.debug("Retrying resolution for domain: #{domain['domain']}")

          # Check if we've exceeded max retries
          if domain['retry_count'] >= @max_retries
            Core.container.logger.info("Max retries exceeded for domain: #{domain['domain']}, removing from database")
            Core.container.database.remove_unresolvable_domain(domain['domain'])
            next
          end

          # Try to resolve the domain
          ip = Core.container.domain_resolver.resolve(domain['domain'])

          if ip
            Core.container.logger.info("Successfully resolved previously unresolvable domain: #{domain['domain']} to IP: #{ip}")

            # Check if IP is private
            if Core.container.domain_resolver.private_ip?(ip)
              Core.container.logger.info("Domain #{domain['domain']} resolved to private IP: #{ip}, removing from unresolvable")
            else
              Core.container.logger.info("Domain #{domain['domain']} resolved to public IP: #{ip}, sending notification")
              program_info = Core.container.database.get_program_for_domain(domain['domain'])
              Core.container.discord_notifier.send_message(domain['domain'], ip, program_info)
              Core.container.fingerprinter.send(domain['domain'])
              Core.container.database.add_discovered_domain(
                domain['domain'],
                ip,
                program_info ? program_info['program'] : nil
              )
            end
            Core.container.database.remove_unresolvable_domain(domain['domain'])
          else
            # Increment retry count
            Core.container.database.increment_retry_count(domain['domain'])
          end
        end
      end
    end
  end
end
