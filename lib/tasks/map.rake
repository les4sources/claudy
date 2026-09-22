# L'import d'un fond de carte dans Claudy (epic #348, phase 1).
#
# Les tuiles arrivent d'un traitement fait à part (téléchargement du vol drone,
# conversion TMS → XYZ, découpe) : cette tâche ne les fabrique pas, elle les
# INSTALLE — copie sous `storage/map-tiles/<clé>/` et enregistrement de la
# couche avec son emprise et ses zooms.
#
# Idempotente : relancée sur la même source, elle recopie les tuiles et met à
# jour la ligne, sans jamais en créer une seconde.

# Les helpers vivent dans un module nommé plutôt qu'en méthodes de haut niveau :
# une méthode définie à la racine d'un `.rake` atterrit sur `Object` et devient
# appelable depuis n'importe quel modèle de l'application.
module MapImportHelpers
  module_function

  # `ENV` rend ses valeurs dans l'encodage de la locale du processus. Sur un
  # serveur en locale C — ou dans un runner de test sans `LANG` — « Ahinvaux
  # (mai 2023) » revient en ASCII-8BIT, et la moindre interpolation avec une
  # chaîne française du script lève `Encoding::CompatibilityError`. On force
  # donc l'UTF-8 à l'entrée, une fois, plutôt que de s'en méfier partout.
  def utf8(value)
    return nil if value.nil?

    value.to_s.dup.force_encoding(Encoding::UTF_8)
  end

  def read_metadata(source)
    fichier = source.join("metadata.json")
    return {} unless fichier.file?

    JSON.parse(fichier.read)
  rescue JSON::ParserError => e
    abort "metadata.json illisible : #{e.message}"
  end

  # Le format produit par le téléchargement : `bounds.sw` / `bounds.ne` en
  # {lat, lng}. On le traduit ici dans la forme que Leaflet attend, une seule
  # fois, plutôt qu'à chaque lecture côté vue.
  def bounds_from(metadata)
    sw = metadata.dig("bounds", "sw")
    ne = metadata.dig("bounds", "ne")
    return nil if sw.blank? || ne.blank?

    { "south" => sw["lat"], "west" => sw["lng"], "north" => ne["lat"], "east" => ne["lng"] }
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue Date::Error
    abort "DATE= n'est pas une date lisible : #{value}"
  end

  # La couche seule, sans copie de fichiers : c'est la partie que les specs
  # exercent, et celle qui doit échouer AVANT qu'on recopie 100 Mo pour rien.
  def upsert_layer(key:, source:, name: nil, date: nil, make_default: false)
    metadata = read_metadata(source)
    couche = MapBaseLayer.find_or_initialize_by(key: key)
    couche.name = utf8(name).presence || couche.name.presence || key
    couche.captured_on = parse_date(date) || couche.captured_on
    couche.min_zoom = metadata.dig("zoom", "min") || couche.min_zoom
    couche.max_zoom = metadata.dig("zoom", "max") || couche.max_zoom
    couche.bounds = bounds_from(metadata) || couche.bounds
    couche.has_relief = source.join("dem").directory?
    couche.default = true if make_default
    couche.save!
    couche
  end

  # `cp_r` sur le CONTENU (le `/.`) plutôt que sur le dossier : sans lui, une
  # seconde exécution imbriquerait `rgb/rgb`.
  def copy_tiles(couche, source)
    MapBaseLayer::KINDS.filter_map do |kind|
      origine = source.join(kind)
      next unless origine.directory?

      cible = couche.tiles_root.join(kind)
      FileUtils.mkdir_p(cible)
      FileUtils.cp_r("#{origine}/.", cible)
      [kind, Dir.glob(cible.join("**", "*.png")).size]
    end
  end
end

namespace :map do
  namespace :base_layer do
    desc "Importer un fond de carte : KEY= NAME= [DATE=] SRC=/chemin [DEFAULT=1]"
    task import: :environment do
      key = MapImportHelpers.utf8(ENV["KEY"]).to_s.strip
      src = MapImportHelpers.utf8(ENV["SRC"]).to_s.strip
      abort "KEY= est obligatoire (ex. KEY=ahinvaux-2023)" if key.blank?
      abort "SRC= est obligatoire (le dossier contenant rgb/ et metadata.json)" if src.blank?

      source = Pathname.new(File.expand_path(src))
      abort "Source introuvable : #{source}" unless source.directory?

      # La couche d'abord, les fichiers ensuite : une clé refusée ne doit pas
      # laisser 100 Mo recopiés à effacer à la main.
      couche = MapImportHelpers.upsert_layer(
        key: key, source: source, name: ENV["NAME"], date: ENV["DATE"],
        make_default: ENV["DEFAULT"].present?
      )

      MapImportHelpers.copy_tiles(couche, source).each do |kind, count|
        puts "  #{kind} : #{count} tuiles sous #{couche.tiles_root.join(kind)}"
      end

      puts "Fond « #{couche.name} » (#{couche.key}) importé — zoom #{couche.min_zoom}–#{couche.max_zoom}, " \
           "relief #{couche.has_relief ? 'oui' : 'non'}#{couche.default? ? ', par défaut' : ''}."
    end
  end
end
