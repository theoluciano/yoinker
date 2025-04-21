require 'httparty'

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

  def find_component_matches
    puts "Getting file list..."
    start = Time.now

    files = get_project_files
    puts "FILES DATA:"
    puts files.inspect
    puts "Fetched #{files.size} files. Scanning now..."

    threads = files.map do |file|
      Thread.new do
        begin
          if file.is_a?(Hash) && file["key"]
            doc = get_file_document(file["key"])
            search_nodes_recursively(doc["document"], file["name"], file["key"])
          else
            Rails.logger.warn("Invalid file format: #{file.inspect}")
            []
          end
        rescue => e
          file_name = file.is_a?(Hash) ? file["name"] : "unknown file"
          Rails.logger.warn("Failed to scan #{file_name}: #{e.message}")
          []
        end
      end
    end

    results = threads.flat_map(&:value)
    puts "Done in #{Time.now - start} seconds"

    results
  end

  private

  def get_project_files
    cache_path = Rails.root.join("tmp", "figma_project_files.json")

    if File.exist?(cache_path)
      begin
        parsed = JSON.parse(File.read(cache_path))
        return parsed.is_a?(Array) ? parsed : (parsed["files"] || [])
      rescue => e
        Rails.logger.warn("Failed to read project files cache: #{e.message}")
        File.delete(cache_path) if File.exist?(cache_path)
      end
    end

    res = self.class.get("/projects/#{@project_id}/files", headers: @headers)
    File.write(cache_path, res.body)
    JSON.parse(res.body)["files"] || []
  end

  def get_file_document(file_key)
    cache_path = Rails.root.join("tmp", "figma_cache_#{file_key}.json")

    if File.exist?(cache_path)
      JSON.parse(File.read(cache_path))
    else
      res = self.class.get("/files/#{file_key}", headers: @headers)
      File.write(cache_path, res.body)
      res.parsed_response
    end
  end

  def search_nodes_recursively(node, file_name, file_key, results = [])
    if node["type"] == "COMPONENT" || node["type"] == "INSTANCE"
      puts "Scanning node: #{node["name"]} (#{node["type"]})"

      if node["type"] == "INSTANCE" && node["mainComponent"]
        main_name = node["mainComponent"]["name"]
        puts "  ↳ Instance of: #{main_name}"
      end
    end

    if node["name"]&.downcase&.include?(@component_name.downcase) && ["COMPONENT", "INSTANCE"].include?(node["type"])
      results << {
        name: node["name"],
        file: file_name,
        file_key: file_key,
        node_id: node["id"],
        type: node["type"]
      }
    end

    if node["children"]
      node["children"].each do |child|
        search_nodes_recursively(child, file_name, file_key, results)
      end
    end

    results
  end
end
