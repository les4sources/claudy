module Reservations
  # La règle de la nuit de week-end seule (epic #260, décision 3).
  #
  # Le site ne vend une nuit de vendredi ou de samedi à l'unité que du
  # 15 novembre au 14 mars. Le reste de l'année, le week-end se loue par paire —
  # et le funnel l'affiche déjà (« Les hébergements se louent pour 2 nuits
  # minimum le week-end »). Il ne le REFUSAIT pas : le JS du calendrier cascade
  # vendredi ↔ samedi, mais il ne peut rien sur un séjour d'une seule nuit.
  #
  # Un seul endroit dit la règle, pour que le refus du Builder, le message du
  # devis live et le bouton bloqué du funnel racontent exactement la même chose.
  module WeekendNightRule
    module_function

    # Les nuits de week-end orphelines d'un draft, dans l'ordre.
    def orphans(draft)
      return [] if draft.nil?

      PricingModel.new(draft).unpriceable_lodging_nights.sort
    end

    def violated?(draft) = orphans(draft).any?

    def message_for(draft)
      found = orphans(draft)
      return nil if found.empty?

      message(found)
    end

    # On nomme la nuit qui MANQUE, pas celle qui gêne : un vendredi orphelin
    # appelle le samedi qui suit, un samedi orphelin le vendredi qui précède.
    def message(orphan_nights)
      missing = orphan_nights.map { |night|
        night.wday == Pricing::LodgingGrid::FRIDAY ? night + 1 : night - 1
      }.uniq.map { |night| night_label(night) }.to_sentence

      "Le week-end, les gîtes se louent 2 nuits minimum (vendredi + samedi), " \
        "sauf du 15 novembre au 14 mars. Ajoutez la nuit du #{missing} " \
        "ou choisissez d'autres dates."
    end

    # « samedi 17 octobre 2026 » — le jour de la semaine EN PREMIER : c'est lui
    # que le client cherche quand on lui parle de vendredi et de samedi.
    def night_label(night)
      "#{I18n.l(night, format: '%A').downcase} #{I18n.l(night, format: :long).strip}"
    end
  end
end
