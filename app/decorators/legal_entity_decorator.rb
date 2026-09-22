# Ce que l'entité dit d'elle-même quand on refuse de la supprimer.
#
# Le refus vivait en une phrase figée dans le contrôleur — « porte des exercices
# ou des écritures — désactive-la » — vraie pour tous les cas et utile pour
# aucun : elle conseillait la désactivation à une entité créée par erreur, qui
# ne portait qu'un exercice vide et qu'il suffisait de débarrasser de cet
# exercice pour supprimer pour de bon.
class LegalEntityDecorator < ApplicationDecorator
  delegate_all

  BLOCKER_LABELS = {
    fiscal_years: ["exercice", "exercices"],
    cash_accounts: ["compte de trésorerie", "comptes de trésorerie"],
    journal_entries: ["écriture", "écritures"]
  }.freeze

  # « 1 exercice », « 3 écritures et 2 comptes de trésorerie » — ce qui bloque
  # vraiment, avec son compte, pour qu'on sache où aller regarder.
  def blockers_sentence
    object.deletion_blockers.map { |kind, count| "#{count} #{noun_for(kind, count)}" }.to_sentence
  end

  # Le message du refus de suppression. Deux conseils, parce qu'il y a deux
  # situations : une entité créée par erreur se supprime (on retire son exercice
  # vide d'abord), une entité qui porte une vraie comptabilité se désactive.
  def deletion_refusal
    return empty_fiscal_years_refusal if object.blocked_only_by_empty_fiscal_years?

    parts = ["Cette entité porte #{blockers_sentence} — désactive-la plutôt que de la supprimer."]
    parts << closed_years_sentence if object.closed_fiscal_years.any?
    h.safe_join(parts, " ")
  end

  private

  def empty_fiscal_years_refusal
    count = object.removable_fiscal_years.size
    h.safe_join(
      ["Cette entité porte #{count} #{noun_for(:fiscal_years, count)}, ",
       "sans aucune écriture ni compte de trésorerie. ",
       h.link_to("Supprime-#{count > 1 ? 'les' : 'le'} depuis les exercices",
                 h.finance_fiscal_years_path(legal_entity_id: object.id),
                 class: "underline font-medium"),
       " et l'entité se supprimera ensuite — pas besoin de la désactiver."]
    )
  end

  # La règle de `fiscal_years#index` : une fois clôturé, un exercice n'a plus de
  # bouton « Supprimer » — on ne défait pas un arrêté d'un clic. Le refus la
  # reprend au lieu d'envoyer l'utilisateur chercher un bouton qui n'existe pas.
  def closed_years_sentence
    count = object.closed_fiscal_years.size
    subject = count > 1 ? "#{count} de ses exercices sont clôturés" : "Son exercice est clôturé"
    "#{subject} : un exercice clôturé ne se supprime pas."
  end

  def noun_for(kind, count)
    singular, plural = BLOCKER_LABELS.fetch(kind)
    count > 1 ? plural : singular
  end
end
