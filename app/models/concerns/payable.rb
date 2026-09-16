# Ce que la maison doit à quelqu'un (epic #240, phase 4).
#
# Cinq choses suffisent à payer : combien, à qui, sur quel compte, avec quelle
# communication, pour quand. Une facture d'achat les porte ; demain une note de
# frais, un relevé de porteur d'activité, une part d'événement, un relevé de
# tiny house ou un règlement de dépôt-vente les porteront aussi — chacun dans sa
# table, avec ses propres statuts. Sans ce contrat commun, la file « À payer »
# se réécrirait entièrement à chaque nouveau type de dette, et chacun
# inventerait son vocabulaire (`amount_due`, `total_cents`, `net_cents`…).
#
# LE PAIEMENT EST UN RAPPROCHEMENT (décision 4), jamais une case à cocher. D'où
# l'association `cash_allocations` polymorphique posée ici : ce qui est payé,
# c'est ce que les lignes de trésorerie affectées couvrent — et si on défait
# l'affectation, la dette redevient due. Un état qui ne sait que monter ment.
#
# Les modèles qui incluent ce concern DOIVENT répondre à `payable_amount_cents`,
# `payable_beneficiary` et `payable_third_party`. Le reste a un défaut
# raisonnable et se surcharge au besoin.
module Payable
  extend ActiveSupport::Concern

  included do
    has_many :cash_allocations, as: :document, dependent: :nullify
  end

  # --- Le contrat, à remplir par chaque payable ------------------------------

  # Ce qu'il reste à sortir de la trésorerie, en centimes, TOUJOURS positif.
  def payable_amount_cents
    raise NotImplementedError, "#{self.class} doit dire combien il doit (payable_amount_cents)"
  end

  # Qui reçoit l'argent, tel qu'on l'écrit sur un virement.
  def payable_beneficiary
    raise NotImplementedError, "#{self.class} doit dire à qui il doit (payable_beneficiary)"
  end

  # Le tiers comptable porté par l'allocation sur le `440000`.
  def payable_third_party
    raise NotImplementedError, "#{self.class} doit porter un tiers (payable_third_party)"
  end

  def payable_iban = payable_third_party&.iban
  def payable_communication = nil
  def payable_due_on = nil
  def payable_reference = "##{id}"
  def payable_label = "#{self.class.model_name.human} #{payable_reference}"
  def payable_path = nil

  # --- Ce qui se déduit du rapprochement -------------------------------------

  def allocated_cents = cash_allocations.sum(:amount_cents).abs
  def remaining_cents = payable_amount_cents - allocated_cents
  def payable_settled? = payable_amount_cents.positive? && allocated_cents >= payable_amount_cents
  def partially_paid? = allocated_cents.positive? && !payable_settled?

  # En retard = l'échéance est passée ET ce n'est pas soldé. Un payable sans
  # échéance n'est jamais en retard : il n'a pas de promesse à tenir.
  def payable_overdue?(on = Date.current)
    payable_due_on.present? && payable_due_on < on && !payable_settled?
  end

  def payable_days_late(on = Date.current)
    return 0 unless payable_overdue?(on)

    (on - payable_due_on).to_i
  end

  # Un virement sans IBAN ne part pas. On ne CACHE jamais pour autant un payable
  # sans coordonnées — faire disparaître une dette parce qu'il manque un champ
  # est la meilleure façon de ne jamais la payer.
  def payable_ready? = payable_iban.present?
end
