class FigmaSearchController < ApplicationController
  def index
    @results = []

    if params[:component].present?
      scanner = FigmaScanner.new(ENV.fetch("FIGMA_PROJECT_ID"), params[:component])
      @results = scanner.find_component_matches
    end
  end
end