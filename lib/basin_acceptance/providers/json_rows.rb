require "json"

module BasinAcceptance
  module Provider
    class JsonRows
      def initialize(stream, label)
        @stream = stream
        @label = label
      end

      def next_row
        loop do
          line = @stream.next_line
          return nil if line.nil?

          text = line.strip
          return JSON.parse(text) unless text.empty?
        end
      rescue JSON::ParserError => error
        raise Error, "#{@label} emitted invalid JSON: #{error.message}"
      end

      def close
        @stream.close
      end
    end
  end
end
