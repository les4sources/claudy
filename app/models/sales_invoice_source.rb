# Le lien entre une facture de vente et ce qu'elle facture (epic #240, phase 6).
#
# Cette table N'EXISTE QUE pour un invariant : une source ne peut être facturée
# qu'une seule fois. Une facture peut en couvrir plusieurs (un séjour et la
# salle qui va avec), mais un séjour déjà facturé ne repart jamais dans une
# seconde facture — c'est l'erreur que la file de facturation ne savait pas
# empêcher.
class SalesInvoiceSource < ApplicationRecord
  # `Booking` n'est pas dans le texte de l'epic (qui ne cite que `Stay` et
  # `SpaceBooking`), mais la file de facturation le liste : des réservations
  # d'hébergement historiques y attendent encore leur facture. Les exclure
  # aurait privé ces lignes du nouveau geste.
  SOURCE_TYPES = %w[Stay SpaceBooking Booking].freeze

  has_paper_trail

  belongs_to :sales_invoice
  belongs_to :source, polymorphic: true

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_id, uniqueness: { scope: :source_type,
                                      message: "est déjà rattaché à une facture de vente" }

  def source_label
    case source
    when Stay then source.decorate.display_name.presence || "Séjour ##{source.id}"
    when SpaceBooking then source.try(:group_name).presence || "Réservation d'espace ##{source.id}"
    else "#{source_type} ##{source_id}"
    end
  end
end
