# La Vue d'ensemble de la Comptabilité, nouvelle interface (redesign, Michael
# 2026-10-29) : la réponse à « Peut-on dépenser ? » dite en une phrase, avec le
# montant qui compte surligné. Les chiffres viennent tous de
# `Finance::SpendingVerdict` : la phrase les met en mots, elle n'en calcule
# aucun.
module AccountingOverviewHelper
  # « 12 480 € » : sans centimes, espace fine entre les milliers, comme la
  # maquette. Les centimes restent dans le détail du calcul.
  def accounting_euros(cents)
    number_to_currency(cents / 100.0, unit: "€", precision: 0, format: "%n %u", delimiter: " ", negative_format: "−%n %u")
  end

  # « la Fondation », « la SRL » : le titre de la courbe parle comme on parle.
  def accounting_entity_short(entity)
    "la #{entity.form_label}"
  end

  # [avant, surligné, après]. Le surligné est LE montant qui répond : ce qu'on
  # peut engager quand c'est oui, le point bas quand il faut être prudent, ce
  # qui manque quand c'est non.
  def accounting_phrase(verdict)
    return ["Impossible à dire : aucun compte de trésorerie actif.", nil, nil] if verdict.nil?

    low = verdict.lowest_point
    when_low = low.date == verdict.treasury.today ? "aujourd’hui" : "le #{l(low.date, format: '%-d %B')}"
    case verdict.verdict
    when "oui"
      ["Oui, jusqu’à ", accounting_euros(verdict.spendable_cents),
       " en gardant un mois de charges fixes de côté. Au plus bas, il restera #{accounting_euros(low.balance_cents)} #{when_low}."]
    when "prudence"
      ["Oui, prudemment : seulement l’indispensable. Au plus bas, il restera ", accounting_euros(low.balance_cents),
       " #{when_low}, après les factures et les charges fixes."]
    when "non"
      if verdict.margin_cents.negative?
        ["Non. Ce qui est en banque est déjà dû : il manque ", accounting_euros(-verdict.margin_cents),
         " pour couvrir les dettes, les prêts et les #{Finance::Treasury::HORIZON_DAYS} jours qui viennent."]
      else
        ["Non. La trésorerie passerait sous zéro : ", accounting_euros(low.balance_cents), " au plus bas, #{when_low}."]
      end
    else
      ["Impossible à dire : aucun compte de #{accounting_entity_short(verdict.entity)} n’a de solde vérifié.", nil, nil]
    end
  end

  # « vérifiés le 22 octobre », « il y a 12 jours » au-delà d'une semaine : un
  # solde ancien doit se lire ancien.
  def accounting_as_of(treasury)
    return "aucun solde vérifié" if treasury.as_of.nil?

    days = (treasury.today - treasury.as_of).to_i
    return "disponibles, vérifiés il y a #{days} jours" if days > 7

    "disponibles, vérifiés le #{l(treasury.as_of, format: '%-d %B')}"
  end

  # « comptée il y a 12 jours », « comptée aujourd’hui ».
  def accounting_counted_ago(days)
    case days
    when 0 then "comptée aujourd’hui"
    when 1 then "comptée hier"
    else "comptée il y a #{days} jours"
    end
  end

  # Une échéance dit ce qu'elle coûte quand sa facture est là, sinon son état.
  def accounting_deadline_side(deadline)
    if deadline.overdue?
      ui_status(:no, "En retard")
    elsif deadline.purchase_invoice&.amount_cents.to_i.positive?
      content_tag(:b, accounting_euros(deadline.purchase_invoice.amount_cents), class: "ui-acc-dl-amount")
    elsif deadline.effective_status == "in_progress"
      ui_status(:pre, "En cours")
    else
      ui_status(:todo, "À préparer")
    end
  end
end
