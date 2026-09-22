module FinanceHelper
  # La communication d'un virement, débarrassée du suffixe que colle l'import
  # CODA (issue #349 bis, Michael 2026-09-20).
  #
  # Une ligne Triodos arrive avec « Tisanes 001Vanhamme - de Tiege » : la
  # banque agrafe `001` puis le nom de la contrepartie à la fin de chaque
  # communication. Ce nom est déjà affiché juste en dessous, et l'écran « À
  # affecter » se lit d'abord par la communication — la laisser traîner, c'est
  # mettre du bruit exactement là où l'œil se pose en premier.
  #
  # On ne coupe QUE si ce qui suit `001` est bien la contrepartie : une
  # communication qui contiendrait `001` pour ses propres raisons — une
  # référence structurée, un numéro de facture — reste intacte.
  def communication_sans_suffixe_coda(entry)
    texte = entry.communication.to_s.strip
    tiers = entry.counterparty_name.to_s.strip
    return texte if texte.blank? || tiers.blank?

    # Le résultat peut être VIDE, et c'est un cas réel : « 001BOLDUC BENJAMIN »
    # est une communication qui ne dit rien d'autre que la contrepartie. La
    # rendre vide fait afficher « Sans communication », ce qui est la vérité —
    # retomber sur le texte d'origine réafficherait le bruit qu'on enlève.
    texte.sub(/\s*001\s*#{Regexp.escape(tiers)}\s*\z/i, "")
  end

  # Ce qu'on lit en PREMIER sur une ligne de la file « À affecter ».
  #
  # La communication d'abord — c'est ce qu'on scanne. À défaut, le libellé de
  # la ligne : une écriture de caisse saisie à la main ou un versement Stripe
  # n'ont pas de communication, et leur libellé est la seule chose lisible
  # qu'elles portent. Afficher « Sans communication » à leur place effacerait
  # la seule information de la ligne.
  #
  # Mais une communication qui ne contenait QUE le suffixe CODA ne retombe pas
  # sur le libellé : celui-ci reprend le même bruit (« BOLDUC BENJAMIN — 001
  # BOLDUC BENJAMIN »). Elle vaut alors « pas de communication », ce qui est
  # exact.
  def libelle_principal(entry)
    communication = communication_sans_suffixe_coda(entry)
    return communication if communication.present?
    return nil if entry.communication.present?

    entry.label.presence
  end

  # Où va-t-on pour lever une étape de l'arrêté du mois ?
  #
  # Le service ne connaît pas les routes — il rend un symbole d'intention. Un
  # écran qui dit « il manque quelque chose » sans dire où aller fait perdre le
  # temps qu'il prétend faire gagner : c'est ici qu'on referme cette boucle.
  def monthly_close_action_path(step, month)
    return nil if step.action_path.blank?

    periode = month.strftime("%Y-%m")

    case step.action_path
    when :coda then finance_coda_imports_path
    when :cash_entries then finance_cash_entries_path
    when :unallocated then finance_unallocated_cash_entries_path
    # « À affecter », restreint aux comptes Stripe : c'est là qu'atterrit une
    # recette dont la catégorie n'a pas encore de correspondance (epic #250).
    when :stripe_unallocated then finance_unallocated_cash_entries_path(kind: "stripe")
    when :recurring then finance_recurring_charges_path(month: periode)
    when :statements then finance_statements_path(month: periode)
    when :trial_balance
      finance_trial_balance_path(from: month.beginning_of_month, to: month.end_of_month)
    end
  end
end
