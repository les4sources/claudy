# Photothèque des gîtes du funnel public /reservation.
#
# Pourquoi un catalogue en dur plutôt qu'ActiveStorage : ces photos changent une
# ou deux fois par an, il n'existe aucune interface d'admin pour les gérer, et
# les servir en assets Vite évite d'ajouter une dépendance de stockage en
# production pour trois galeries. Changer une photo = un commit. Le jour où
# Michael veut les gérer depuis l'admin, ce fichier devient une table.
#
# L'ORDRE compte : la première photo est la couverture de la carte, et la
# galerie se lit dans cet ordre. On ouvre sur l'espace commun le plus parlant,
# puis cuisine et pièces de vie, puis les chambres, et on termine par le
# fonctionnel. Personne ne choisit un gîte sur une photo de sanitaires.
#
# Le `alt` décrit ce que la photo MONTRE, pour quelqu'un qui ne la voit pas —
# pas « photo du gîte ». Il n'est jamais vide : ces images portent l'essentiel
# de la décision d'achat.
module LodgingPhotosHelper
  Photo = Struct.new(:file, :alt, keyword_init: true) do
    def path = "images/lodgings/#{file}"
  end

  CHEVECHE = [
    Photo.new(file: "cheveche-salle-a-manger.avif", alt: "La salle à manger de la Chevêche : grande table en bois sur un sol en pierre bleue, murs en terre crue."),
    Photo.new(file: "cheveche-salon.avif",          alt: "Le salon de la Chevêche : canapés, applique murale et sol carrelé sombre."),
    Photo.new(file: "cheveche-cuisine.avif",        alt: "La cuisine de la Chevêche, en longueur, équipée d'un four et de plans de travail clairs."),
    Photo.new(file: "cheveche-chambre-lits-superposes.avif", alt: "Chambre de la Chevêche avec lits superposés, lit simple et lavabo, parquet et fenêtre à rideaux."),
    Photo.new(file: "cheveche-chambre-deux-lits.avif", alt: "Chambre de la Chevêche avec deux lits simples sous des poutres apparentes."),
    Photo.new(file: "cheveche-chambre-armoire.avif", alt: "Chambre de la Chevêche avec lits superposés et grande armoire en bois."),
    Photo.new(file: "cheveche-chambre-radiateur.avif", alt: "Chambre de la Chevêche avec lits superposés et lit simple, rideau rouge à la fenêtre.")
  ].freeze

  HULOTTE = [
    Photo.new(file: "hulotte-salle-commune.avif", alt: "La grande salle commune de la Hulotte, sous charpente, avec ses longues tables en bois et ses fenêtres de toit."),
    Photo.new(file: "hulotte-cuisine.avif",       alt: "La cuisine de la Hulotte : four, gazinière et plans de travail clairs sur parquet."),
    Photo.new(file: "hulotte-cuisine-mansardee.avif", alt: "Coin cuisine mansardé de la Hulotte, avec table sous la fenêtre de toit."),
    Photo.new(file: "hulotte-coin-salon.avif",    alt: "Coin salon de la Hulotte : banquette rouge sous la charpente."),
    Photo.new(file: "hulotte-mezzanine.avif",     alt: "La mezzanine de la Hulotte, avec sa banquette longue et son garde-corps en filet."),
    Photo.new(file: "hulotte-chambre-deux-lits.avif", alt: "Chambre de la Hulotte avec plusieurs lits simples et une fenêtre à rideaux."),
    Photo.new(file: "hulotte-chambre-lavabo.avif", alt: "Chambre de la Hulotte avec trois lits et un lavabo, murs ocre."),
    Photo.new(file: "hulotte-chambre-velux.avif", alt: "Chambre mansardée de la Hulotte avec deux lits sous une fenêtre de toit."),
    Photo.new(file: "hulotte-chambre-ocre.avif",  alt: "Chambre de la Hulotte aux murs terracotta, avec plusieurs lits simples."),
    Photo.new(file: "hulotte-chambre-superposes.avif", alt: "Chambre mansardée de la Hulotte avec lits superposés et lit simple."),
    Photo.new(file: "hulotte-sanitaires.avif",    alt: "Sanitaires de la Hulotte : lavabo, miroir et toilettes.")
  ].freeze

  TERRASSE = Photo.new(
    file: "terrasse-tilleul.avif",
    alt: "La terrasse commune sous le grand tilleul : tables de pique-nique, guirlande lumineuse et vue sur la vallée."
  ).freeze

  # Le Grand-Duc EST la Hulotte + la Chevêche réunies : sa galerie est celle des
  # deux gîtes, ouverte sur l'extérieur commun qu'il est le seul à occuper seul.
  GALLERIES = {
    "La Chevêche"  => [TERRASSE, *CHEVECHE].freeze,
    "La Hulotte"   => [TERRASSE, *HULOTTE].freeze,
    "Le Grand-Duc" => [TERRASSE, *HULOTTE, *CHEVECHE].freeze
  }.freeze

  # Couverture de carte et vignette de grille — dérivés générés à la main
  # (900 px et 200 px) pour ne pas envoyer une image de 1440 px dans un cadre de
  # 400. Chaque gîte a la sienne, distincte, pour qu'on les reconnaisse d'un œil.
  COVER_SLUGS = { "La Chevêche" => "cheveche", "La Hulotte" => "hulotte", "Le Grand-Duc" => "grand-duc" }.freeze
  SLUG_TO_NAME = COVER_SLUGS.invert.freeze

  def lodging_gallery(lodging_name)
    GALLERIES[lodging_name] || []
  end

  # `LodgingPhotosHelper.gallery_for("hulotte")` — utilisé par le contrôleur,
  # qui n'a pas le contexte de vue. Renvoie [] pour un slug inconnu : l'URL est
  # publique, elle ne doit rien lever ni rien révéler.
  def self.gallery_for(slug)
    GALLERIES[SLUG_TO_NAME[slug.to_s]] || []
  end

  def self.name_for(slug)
    SLUG_TO_NAME[slug.to_s]
  end

  def lodging_cover_path(lodging_name)
    slug = COVER_SLUGS[lodging_name]
    slug && "images/lodgings/cover-#{slug}.avif"
  end

  def lodging_thumb_path(lodging_name)
    slug = COVER_SLUGS[lodging_name]
    slug && "images/lodgings/thumb-#{slug}.avif"
  end

  def lodging_has_photos?(lodging_name)
    GALLERIES.key?(lodging_name)
  end
end
