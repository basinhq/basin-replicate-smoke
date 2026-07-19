require_relative "basin_acceptance/cli"
require_relative "basin_acceptance/context"
require_relative "basin_acceptance/preflight"
require_relative "basin_acceptance/providers"
require_relative "basin_acceptance/scenario"
require_relative "basin_acceptance/suite"
require_relative "basin_acceptance/runner"
require_relative "basin_acceptance/report"

module BasinAcceptance
  class Error < StandardError
  end
end
