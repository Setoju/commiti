# frozen_string_literal: true

module Commiti
  module DiffSummarizer
    module BatchRunner
      def summarize_chunks(chunks, client:, model:, worker_count: nil)
        results = Array.new(chunks.length)
        large_jobs = []

        chunks.each_with_index do |chunk, index|
          if chunk[:diff].bytesize > CHUNK_THRESHOLD
            large_jobs << { index: index, chunk: chunk }
          else
            results[index] = format_chunk_summary(path: chunk[:path], summary: mechanical_summary(chunk[:diff]))
          end
        end

        batched_jobs = build_batch_jobs(large_jobs)
        run_async_summary_jobs(batched_jobs, results: results, client: client, model: model, worker_count: worker_count) unless batched_jobs.empty?
        results
      end

      def run_async_summary_jobs(jobs, results:, client:, model:, worker_count: nil)
        queue = Queue.new
        jobs.each { |job| queue << job }

        worker_count_actual = summary_worker_count(jobs.length, configured_count: worker_count)
        captured_errors = Queue.new

        workers = Array.new(worker_count_actual) do
          Thread.new do
            loop do
              job = queue.pop(true)
              process_batch_job(job, results: results, client: client, model: model)
            rescue ThreadError
              break
            rescue StandardError => e
              captured_errors << e
              break
            end
          end
        end

        workers.each(&:join)
        raise captured_errors.pop unless captured_errors.empty?
      end

      def process_batch_job(job, results:, client:, model:)
        items = job[:items]
        if items.length == 1
          item = items.first
          summary = summarize_single_chunk(item[:chunk], client: client, model: model)
          results[item[:index]] = format_chunk_summary(path: item[:chunk][:path], summary: summary)
          return
        end

        summaries = summarize_chunk_batch(items, client: client, model: model)
        items.each do |item|
          summary = summaries[item[:chunk][:path].to_s]
          summary ||= summarize_single_chunk(item[:chunk], client: client, model: model)
          results[item[:index]] = format_chunk_summary(path: item[:chunk][:path], summary: summary)
        end
      end

      def build_batch_jobs(jobs)
        batched = []
        current = []
        current_bytes = 0

        jobs.each do |job|
          chunk_bytes = job[:chunk][:diff].bytesize
          should_split = !current.empty? && (
            current.length >= MAX_BATCH_FILES ||
            current_bytes + chunk_bytes > MAX_BATCH_BYTES
          )

          if should_split
            batched << { items: current }
            current = []
            current_bytes = 0
          end

          current << job
          current_bytes += chunk_bytes
        end

        batched << { items: current } unless current.empty?
        batched
      end

      def summarize_single_chunk(chunk, client:, model:)
        client.generate(
          system: CHUNK_SYSTEM,
          user: "Summarize these changes:\n\n``diff\n#{chunk[:diff]}\n``",
          model: model,
          timeout_seconds: 120,
          open_timeout_seconds: 10
        )
      end

      def summarize_chunk_batch(items, client:, model:)
        user = +"Summarize the following file diffs:\n\n"
        items.each do |item|
          path = item[:chunk][:path]
          diff = item[:chunk][:diff]
          user << "### #{path}\n```diff\n#{diff}\n```\n\n"
        end

        output = client.generate(
          system: BATCH_SYSTEM,
          user: user.rstrip,
          model: model,
          timeout_seconds: 120,
          open_timeout_seconds: 10
        )

        parse_batched_summary_output(output, expected_paths: items.map { |item| item[:chunk][:path].to_s })
      end

      def parse_batched_summary_output(output, expected_paths:)
        sections = output.to_s.split(/^### /).map(&:strip).reject(&:empty?)
        parsed = {}

        sections.each do |section|
          lines = section.lines
          path = lines.first.to_s.strip
          next unless expected_paths.include?(path)

          summary = lines[1..].to_a.join.strip
          parsed[path] = summary unless summary.empty?
        end

        parsed
      end

      def summary_worker_count(job_count, configured_count: nil)
        count = configured_count || Integer(ENV.fetch('DIFF_SUMMARY_WORKERS', DEFAULT_SUMMARY_WORKERS))
        count.clamp(1, job_count)
      rescue ArgumentError
        DEFAULT_SUMMARY_WORKERS.clamp(1, job_count)
      end

      def format_chunk_summary(path:, summary:)
        "### #{path}\n#{summary.to_s.strip}"
      end
    end
  end
end
