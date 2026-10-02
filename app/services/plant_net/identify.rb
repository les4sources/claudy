module PlantNet
  # « Quelle est cette plante ? » depuis la fiche plante : une à cinq photos du
  # même individu partent chez Pl@ntNet, et reviennent en propositions à
  # valider ou refuser une à une.
  #
  # Chaque proposition est rapprochée du catalogue : par le nom latin d'abord
  # (« Malus domestica » retrouve « Pommier (Malus domestica) », variétés
  # comprises), puis par un nom commun quand l'espèce du catalogue n'a pas
  # encore de nom latin. Une espèce inconnue est proposée sous son premier nom
  # français ; elle ne sera créée qu'à l'enregistrement de la fiche, comme une
  # espèce tapée à la main.
  #
  # Les photos sont gardées (blobs non attachés) : la fiche les joint à la
  # plante à l'enregistrement, par leur `signed_id`.
  class Identify
    CONTENT_TYPES = %w[image/jpeg image/png].freeze

    class Invalid < StandardError; end

    Proposal = Data.define(:name, :latin_name, :family, :common_names, :score, :species) do
      def known? = species.present?
      def percent = (score * 100).round
    end

    Result = Data.define(:proposals, :photos)

    def initialize(files:, client: Client.new)
      @files = Array(files).compact_blank
      @client = client
    end

    def run!
      raise Invalid, "Choisissez au moins une photo de la plante." if @files.empty?
      raise Invalid, "#{Client::MAX_IMAGES} photos au plus, du même individu." if @files.size > Client::MAX_IMAGES

      images = @files.map { |file| read(file) }
      candidates = @client.identify(images)
      photos = images.map do |image|
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new(image[:data]), filename: image[:filename],
                                               content_type: image[:content_type])
      end
      Result.new(proposals: candidates.map { |candidate| proposal(candidate) }, photos: photos)
    end

    private

    def read(file)
      content_type = file.content_type.to_s
      unless CONTENT_TYPES.include?(content_type)
        raise Invalid, "« #{file.original_filename} » n'est pas une photo JPEG ou PNG."
      end

      data = file.read
      { io: StringIO.new(data), data: data, filename: file.original_filename.to_s, content_type: content_type }
    end

    def proposal(candidate)
      species = catalog_match(candidate)
      Proposal.new(name: species&.name || new_name(candidate), latin_name: candidate.latin_name,
                   family: candidate.family, common_names: candidate.common_names.first(3),
                   score: candidate.score, species: species)
    end

    def catalog_match(candidate)
      latin = candidate.latin_name.to_s.squish.downcase
      by_latin = PlantSpecies.where("lower(plant_species.latin_name) = :latin OR lower(plant_species.latin_name) LIKE :prefix",
                                    latin: latin, prefix: "#{PlantSpecies.sanitize_sql_like(latin)} %")
                             .order(Arel.sql("length(plant_species.latin_name)")).first
      by_latin || candidate.common_names.lazy.map { |name| PlantSpecies.where(latin_name: nil).named(name).first }.find(&:itself)
    end

    # Le premier nom français (« Pommier »), sinon le nom latin. Un nom déjà pris
    # au catalogue par une AUTRE espèce ne se réutilise pas : la fiche
    # rattacherait la plante à la mauvaise.
    def new_name(candidate)
      name = candidate.common_names.first&.squish&.upcase_first
      name.present? && !PlantSpecies.named(name).exists? ? name : candidate.latin_name
    end
  end
end
