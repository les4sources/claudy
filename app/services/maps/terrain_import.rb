require "net/http"

module Maps
  # Télécharge le relief du domaine depuis le Géoportail (voir `Maps::Terrain`).
  #
  # Le SPW ne publie son MNT qu'en MapServer : ni WCS, ni ImageServer, et le
  # rendu imposé (une rampe de couleurs) refuse tout renderer personnalisé. Mais
  # l'`identify` accepte un MULTIPOINT et rend une valeur de pixel par point, dans
  # l'ordre : 20 000 altitudes par requête, ~9 s. Une grille à 1 m du domaine et
  # de sa marge (~750 000 points) tient en une quarantaine de requêtes.
  #
  # La marge (150 m) sert l'amont : l'eau qui ruisselle sur le domaine vient en
  # partie des pentes voisines, et une simulation coupée au bord de la parcelle
  # la ferait naître au milieu d'un champ.
  class TerrainImport
    MNT_URL = "https://geoservices.wallonie.be/arcgis/rest/services/RELIEF/WALLONIE_MNT_2021_2022/MapServer".freeze
    ORTHO_URL = "https://geoservices.wallonie.be/arcgis/rest/services/IMAGERIE/ORTHO_2026_PRINTEMPS/MapServer".freeze
    CELL_SIZE_M = 1.0
    MARGIN_M = 150.0
    CHUNK = 20_000
    THREADS = 3
    TEXTURE_MAX_PX = 4096
    ATTEMPTS = 3

    class Error < StandardError; end

    Extent = Data.define(:west, :north, :step, :cols, :rows, :lat0) do
      def east = west + (cols - 1) * step
      def south = north - (rows - 1) * step

      def point(index)
        [west + (index % cols) * step, north - (index / cols) * step]
      end
    end

    # `bounds` : { "south", "west", "north", "east" } en WGS84, celles du fond de
    # carte par défaut.
    def self.extent_for(bounds, cell_size_m: CELL_SIZE_M, margin_m: MARGIN_M)
      south, west, north, east = bounds.values_at("south", "west", "north", "east").map(&:to_f)
      lat0 = (south + north) / 2
      # Le facteur d'échelle de Mercator : une unité 3857 vaut cos(lat) mètre.
      scale = 1 / Math.cos(lat0 * Math::PI / 180)
      step = cell_size_m * scale
      margin = margin_m * scale
      x0, y0 = Terrain.to_mercator(south, west)
      x1, y1 = Terrain.to_mercator(north, east)
      west_m = x0 - margin
      north_m = y1 + margin
      cols = (((x1 + margin) - west_m) / step).ceil + 1
      rows = ((north_m - (y0 - margin)) / step).ceil + 1
      Extent.new(west: west_m, north: north_m, step: step, cols: cols, rows: rows, lat0: lat0)
    end

    # `http` : un appelable (url, params) → corps de la réponse ; les specs y
    # branchent un faux SPW.
    def initialize(bounds:, terrain: Terrain.current, logger: nil, http: nil, cell_size_m: CELL_SIZE_M,
                   margin_m: MARGIN_M, chunk: CHUNK)
      @cell_size_m = cell_size_m
      @chunk = chunk
      @extent = self.class.extent_for(bounds, cell_size_m: cell_size_m, margin_m: margin_m)
      @terrain = terrain
      @logger = logger
      @http = http || method(:post_form)
    end

    attr_reader :extent

    def call(texture: true)
      heights = fetch_heights
      write_grid(heights)
      download_texture if texture
      @terrain
    end

    # Les altitudes en mètres (Float, `nil` = pas de donnée), dans l'ordre de la
    # grille. Les paquets partent sur quelques fils : le SPW répond en ~9 s par
    # paquet, séquentiellement l'import prendrait six minutes.
    def fetch_heights
      total = extent.cols * extent.rows
      chunks = (0...total).each_slice(@chunk).to_a
      heights = Array.new(total)
      queue = Queue.new
      chunks.each_with_index { |indexes, i| queue << [i, indexes] }
      done = 0
      mutex = Mutex.new
      errors = []

      workers = Array.new([THREADS, chunks.size].min) do
        Thread.new do
          loop do
            i, indexes = begin
              queue.pop(true)
            rescue ThreadError
              break
            end
            values = fetch_chunk(indexes)
            mutex.synchronize do
              indexes.each_with_index { |index, j| heights[index] = values[j] }
              done += 1
              log("paquet #{done}/#{chunks.size}")
            end
          rescue StandardError => e
            mutex.synchronize { errors << e }
            break
          end
        end
      end
      workers.each(&:join)
      raise errors.first if errors.any?

      heights
    end

    def fetch_chunk(indexes)
      points = indexes.map { |index| extent.point(index).map { |v| v.round(3) } }
      params = {
        f: "json", geometryType: "esriGeometryMultipoint", sr: "3857", layers: "all:0", tolerance: "0",
        returnGeometry: "false", imageDisplay: "1000,1000,96",
        mapExtent: [extent.west, extent.south, extent.east, extent.north].map { |v| v.round(3) }.join(","),
        geometry: { points: points, spatialReference: { wkid: 3857 } }.to_json
      }
      attempt = 0
      begin
        attempt += 1
        body = JSON.parse(@http.call("#{MNT_URL}/identify", params))
        raise Error, body["error"].to_json if body["error"]

        results = body["results"] || []
        # L'ordre des résultats EST l'ordre des points : un paquet incomplet
        # décalerait toute la grille, on refuse plutôt que de deviner.
        raise Error, "#{results.size} altitudes pour #{points.size} points" unless results.size == points.size

        results.map { |result| parse_height(result["attributes"]) }
      rescue Error, JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET => e
        raise if attempt >= ATTEMPTS

        log("nouvel essai (#{e.class}: #{e.message.to_s[0, 120]})")
        sleep 2 * attempt
        retry
      end
    end

    def write_grid(heights)
      known = heights.compact
      raise Error, "aucune altitude reçue" if known.empty?

      z_min = known.min.floor(2)
      z_max = known.max
      packed = heights.map { |z| z.nil? ? Terrain::NODATA : ((z - z_min) * 100).round.clamp(0, Terrain::NODATA - 1) }
      FileUtils.mkdir_p(@terrain.root)
      File.binwrite(@terrain.grid_path, packed.pack("v*"))
      write_metadata(z_min: z_min, z_max: z_max, nodata_count: heights.size - known.size)
    end

    # L'ortho de printemps 2026 sur l'emprise exacte des centres de mailles. Le
    # rapport largeur/hauteur de l'image suit celui de l'emprise : ArcGIS
    # élargirait sinon la boîte demandée, et la photo glisserait sur le relief.
    def download_texture
      width_m = extent.east - extent.west
      height_m = extent.north - extent.south
      width = [TEXTURE_MAX_PX, (TEXTURE_MAX_PX * width_m / height_m).round].min
      height = (width * height_m / width_m).round
      params = { f: "image", format: "jpg", bboxSR: "3857", imageSR: "3857", size: "#{width},#{height}",
                 bbox: [extent.west, extent.south, extent.east, extent.north].map { |v| v.round(3) }.join(",") }
      image = @http.call("#{ORTHO_URL}/export", params)
      raise Error, "l'ortho n'est pas une image JPEG" unless image.to_s.b.start_with?("\xFF\xD8".b)

      File.binwrite(@terrain.texture_path, image)
      write_metadata(**metadata_base, texture: { width: width, height: height, source: "SPW, ortho printemps 2026" })
    end

    private

    def parse_height(attributes)
      value = attributes.to_h.values.first
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def metadata_base
      @terrain.metadata.symbolize_keys.slice(:z_min, :z_max, :nodata_count)
    end

    def write_metadata(z_min:, z_max:, nodata_count:, texture: nil)
      data = {
        key: Terrain::KEY, source: "SPW, MNT LiDAR 2021-2022 (50 cm, terrain nu)", source_url: MNT_URL,
        fetched_at: Time.current.iso8601, crs: "EPSG:3857",
        west: extent.west, north: extent.north, step: extent.step, cols: extent.cols, rows: extent.rows,
        cell_size_m: @cell_size_m, lat0: extent.lat0, z_min: z_min, z_max: z_max, z_unit: 0.01,
        nodata: Terrain::NODATA, nodata_count: nodata_count,
        texture: texture || @terrain.metadata["texture"]
      }.compact
      File.write(@terrain.metadata_path, JSON.pretty_generate(data))
    end

    def post_form(url, params)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 90) do |http|
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(params)
        response = http.request(request)
        raise Error, "HTTP #{response.code} sur #{uri.path}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end
    end

    def log(message)
      @logger&.call(message)
    end
  end
end
