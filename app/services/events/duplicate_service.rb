module Events
  # Duplication d'un événement — même parti pris que `Stays::DuplicateService` :
  # rien n'est écrit en base. Le service renvoie un `Event` NEUF, prérempli
  # depuis la source, destiné au formulaire de création. L'éditrice choisit les
  # nouvelles dates et enregistre : c'est la création normale qui persiste.
  #
  # Pourquoi pas un clone immédiat : un événement sans dates ferait planter les
  # vues et le calendrier (`starts_at.to_date`), et un clone aux mêmes dates
  # n'aurait aucun sens pour une pizza party mensuelle.
  #
  # COPIÉ : titre, résumé, description publique, catégorie, lieu, prix, lien
  # d'inscription ; l'image est reprise à la création (`duplicate_of_id`, voir
  # `Events::CreateService`). EXCLU : dates, slug, publication, notes internes,
  # participants et ventes (ils appartiennent à l'édition passée).
  class DuplicateService
    attr_reader :source

    def initialize(event:)
      @source = event
    end

    def call
      copy = Event.new(
        name: source.name,
        summary: source.summary,
        location: source.location,
        price_text: source.price_text,
        url: source.url,
        event_category_id: source.event_category_id,
        duplicate_of_id: source.id
      )
      copy.public_description = source.public_description.body if source.public_description.present?
      copy
    end
  end
end
