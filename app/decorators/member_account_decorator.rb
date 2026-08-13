# Formatage d'affichage d'un compte courant (issue #155). Tout ce qui met en
# forme un montant, un libellé ou une couleur passe ici — jamais par le modèle
# ni par un helper.
class MemberAccountDecorator < ApplicationDecorator
  delegate_all

  def balance
    h.number_to_currency(object.balance_cents / 100.0)
  end

  # Rouge quand le compte doit de l'argent, vert quand il est créditeur.
  def balance_css
    return "text-gray-500" if object.balance_cents.zero?

    object.balance_cents.positive? ? "text-red-600 font-semibold" : "text-emerald-700 font-semibold"
  end

  def opening_balance
    h.number_to_currency(object.opening_balance_cents / 100.0)
  end

  def opening_balance_line
    date = object.opening_balance_on
    return "Solde d'ouverture : #{opening_balance}" if date.blank?

    "Solde d'ouverture au #{h.l(date, format: :long).squish} : #{opening_balance}"
  end

  # « Ménage — Les Chevêches », « Personne », « Entité »
  def anchor_label
    return "#{object.kind_label} — #{object.household.name}" if object.kind == "household" && object.household

    object.kind_label
  end

  def last_entry
    return "—" if object.last_entry_on.blank?

    h.l(object.last_entry_on, format: :long).squish
  end

  def status_badge
    if object.active?
      h.content_tag(:span, "Actif",
                    class: "inline-flex items-center rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700")
    else
      h.content_tag(:span, "Inactif",
                    class: "inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600")
    end
  end
end
