class FigmaSearchController < ApplicationController
  def index
    @projects = FigmaScanner.fetch_projects_for_known_teams || []
    @results = nil
    @searching = params[:component].present? && params[:project_id].present?
  
    if @searching
      scanner = FigmaScanner.new(params[:project_id], params[:component])
      @results = scanner.find_component_matches
    end
  end
end