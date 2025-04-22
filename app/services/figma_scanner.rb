require 'httparty'
require 'json'

class FigmaScanner
  include HTTParty
  base_uri 'https://api.figma.com/v1'

  def initialize(project_id, component_name)
    @project_id = project_id
    @component_name = component_name
    @headers = {
      "X-Figma-Token" => ENV.fetch("FIGMA_PERSONAL_TOKEN")
    }
  end

  def self.fetch_projects_for_known_teams
    team_ids = JSON.parse(ENV.fetch("TEAM_IDS", "{}"))
    all_projects = []

    team_ids.each do |team_name, team_id|
      url = "/teams/#{team_id}/projects"
      res = get(url, headers: { "X-Figma-Token" => ENV.fetch("FIGMA_PERSONAL_TOKEN") })

      if res.code != 200
        puts "❌ Failed to fetch projects for team #{team_name} (#{team_id}): #{res.code} #{res.body}"
        next
      end

      projects = res.parsed_response["projects"] || []
      projects.each do |project|
        all_projects << {
          id: project["id"],
          name: project["name"],
          team: team_name
        }
      end
    rescue => e
      Rails.logger.warn("Failed to load projects for team #{team_name}: #{e.message}")
    end

    all_projects
  end

  def find_component_matches
    start = Time.now

    files = get_project_files
    puts "Scanning #{files.size} files..."

    threads = files.map do |file|
      Thread.new do
        begin
          doc = get_file_document(file["key"])
          search_nodes_recursively(doc["document"], file["name"], file["key"])
        rescue => e
          file_name = file.is_a?(Hash) ? file["name"] : "unknown file"
          Rails.logger.warn("Failed to scan #{file_name}: #{e.message}")
          []
        end
      end
    end

    results = threads.flat_map(&:value)

    puts "Done in #{Time.now - start} seconds"
    puts "Total matches: #{results.size}"
    results
  end

  def get_project_files
    cache_path = Rails.root.join("tmp", "figma_project_#{@project_id}_files.json")

    if File.exist?(cache_path)
      if File.mtime(cache_path) < 24.hours.ago
        File.delete(cache_path)
      else
        begin
          parsed = JSON.parse(File.read(cache_path))
          return parsed.is_a?(Array) ? parsed : (parsed["files"] || [])
        rescue => e
          Rails.logger.warn("Failed to read project file cache: #{e.message}")
          File.delete(cache_path) if File.exist?(cache_path)
        end
      end
    end

    res = self.class.get("/projects/#{@project_id}/files", headers: @headers)
    File.write(cache_path, res.body)
    JSON.parse(res.body)["files"] || []
  end

  def get_file_document(file_key)
    cache_path = Rails.root.join("tmp", "figma_cache_#{@project_id}_#{file_key}.json")

    if File.exist?(cache_path)
      if File.mtime(cache_path) < 24.hours.ago
        File.delete(cache_path)
      else
        return JSON.parse(File.read(cache_path))
      end
    end

    res = self.class.get("/files/#{file_key}", headers: @headers)
    File.write(cache_path, res.body)
    res.parsed_response
  end

  def search_nodes_recursively(node, file_name, file_key, results = [], page_name = nil)
    # Detect if this node is a page (FRAME directly under the document)
    if node["type"] == "CANVAS"
      page_name = node["name"]
    end

    if node["type"] == "INSTANCE"
      name_to_match = node.dig("mainComponent", "name") || node["name"]
      matched = name_to_match&.casecmp(@component_name)&.zero?

      if matched
        results << {
          name: name_to_match,
          file: file_name,
          file_key: file_key,
          node_id: node["id"],
          type: node["type"],
          page: page_name
        }
      end
    end

    if node["children"]
      node["children"].each do |child|
        search_nodes_recursively(child, file_name, file_key, results, page_name)
      end
    end

    results
  end
end
