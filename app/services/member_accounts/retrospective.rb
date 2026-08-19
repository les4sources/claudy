module MemberAccounts
  # Douze mois de compte, lus par la personne dont c'est le compte.
  #
  # Le grand livre répond à « qu'est-ce qui s'est passé le 14 mars » ; il ne
  # répond pas à « où part mon argent » ni à « est-ce que je consomme plus que
  # d'habitude ». Ces deux questions-là sont celles qu'un habitant se pose, et
  # aucune ligne de journal ne les adresse — d'où cette lecture agrégée.
  #
  # La fenêtre par défaut est GLISSANTE sur douze mois : une année civile
  # rendrait la page inutile en janvier, au moment précis où on veut faire le
  # point. Mais comparer une année à la précédente est la question suivante —
  # d'où les périodes nommées (`2025`, `2024`…, `tout`).
  #
  # Pas de sélecteur de dates libre, volontairement : « du 14 mars au 2
  # septembre » n'est une question que personne ne se pose, et deux champs de
  # dates coûteraient plus cher en attention qu'ils ne rapportent.
  class Retrospective
    MOIS = 12
    GLISSANTE = "12m".freeze
    TOUT = "tout".freeze

    # Chaque canal garde SA couleur d'un bout à l'autre de la page — dans le
    # ruban des mois, dans la barre de répartition, dans la légende. C'est ce
    # qui permet de lire le graphique sans faire l'aller-retour vers la
    # légende à chaque colonne.
    #
    # Les teintes viennent de la charte « sous-bois » du portail (cuivre, vert
    # forêt, terre cuite, mousse) et non de la palette générique : la page se
    # lit sur fond sable, où huit couleurs saturées se battraient entre elles.
    COULEURS = {
      "bar" => "#C97B3D",
      "grocery" => "#12524D",
      "meal" => "#A6572E",
      "pot" => "#7A6A9B",
      "dome" => "#3C7C8C",
      "pet" => "#8C6239",
      "charges" => "#5C6659",
      "other" => "#A79D89"
    }.freeze
    COULEUR_PAR_DEFAUT = "#A79D89".freeze

    Mois = Struct.new(:month, :par_flow, :total_cents, keyword_init: true)
    Canal = Struct.new(:flow, :label, :couleur, :amount_cents, :part, keyword_init: true)
    Article = Struct.new(:name, :quantity, :amount_cents, keyword_init: true)

    def initialize(member_account, periode: GLISSANTE, today: Date.current)
      @account = member_account
      @today = today
      @periode = periode.to_s.presence || GLISSANTE
    end

    # Une période inconnue retombe sur la fenêtre glissante plutôt que de
    # lever : le paramètre vient de l'URL, et une URL bricolée ne doit pas
    # rendre une 500.
    def periode
      @periode_retenue ||= periodes_disponibles.include?(@periode) ? @periode : GLISSANTE
    end

    # Les choix offerts : la fenêtre glissante, chaque année civile où le compte
    # a bougé, et tout l'historique — proposé seulement s'il dépasse une année,
    # sinon il ferait doublon avec la fenêtre glissante.
    def periodes_disponibles
      @periodes_disponibles ||= begin
        annees = annees_actives.map(&:to_s)
        [GLISSANTE, *annees.reverse, (TOUT if annees.size > 1)].compact
      end
    end

    def libelle_periode(valeur = periode)
      case valeur
      when GLISSANTE then "12 derniers mois"
      when TOUT then "Tout l'historique"
      else valeur
      end
    end

    def debut
      @debut ||= case periode
                 when GLISSANTE then @today.beginning_of_month - (MOIS - 1).months
                 when TOUT then (premiere_ecriture || @today).beginning_of_month
                 else Date.new(periode.to_i, 1, 1)
                 end
    end

    # Une année en cours s'arrête au mois courant : douze colonnes dont sept
    # vides diraient « le compte s'est arrêté », pas « l'année n'est pas finie ».
    def fin
      @fin ||= case periode
               when GLISSANTE, TOUT then @today.end_of_month
               else [Date.new(periode.to_i, 12, 31), @today.end_of_month].min
               end
    end

    def nombre_de_mois
      @nombre_de_mois ||= ((fin.year * 12 + fin.month) - (debut.year * 12 + debut.month)) + 1
    end

    # Un mois par colonne, même vide : un trou dans la série se lit, une
    # colonne manquante se confond avec le mois voisin.
    def mois
      @mois ||= (0...nombre_de_mois).map do |decalage|
        month = debut + decalage.months
        par_flow = depenses_par_mois_et_flow[month] || {}
        Mois.new(month: month, par_flow: par_flow, total_cents: par_flow.values.sum)
      end
    end

    # Les canaux du plus gros au plus petit — l'ordre dans lequel la question
    # « où part mon argent » se répond.
    def canaux
      @canaux ||= begin
        total = total_depense_cents
        depenses_par_flow.sort_by { |_flow, cents| -cents }.map do |flow, cents|
          Canal.new(flow: flow, label: AccountEntry::FLOW_LABELS.fetch(flow, "Divers"),
                    couleur: COULEURS.fetch(flow, COULEUR_PAR_DEFAUT), amount_cents: cents,
                    part: total.zero? ? 0.0 : (cents * 100.0 / total))
        end
      end
    end

    def total_depense_cents = @total_depense_cents ||= depenses_par_flow.values.sum

    # Ce qui est rentré : règlements et avoirs, comptés positivement.
    def total_regle_cents
      @total_regle_cents ||= -ecritures.where(amount_cents: ...0).sum(:amount_cents)
    end

    # La moyenne se calcule sur les mois RÉELLEMENT ouverts, pas sur douze :
    # un compte créé en mai afficherait sinon une moyenne divisée par deux.
    def moyenne_mensuelle_cents
      actifs = mois.count { |m| m.total_cents.positive? }
      return 0 if actifs.zero?

      total_depense_cents / actifs
    end

    def mois_le_plus_charge = mois.max_by(&:total_cents)

    def plafond_cents = mois.map(&:total_cents).max.to_i

    # Ce qu'on consomme le plus souvent, quand les lignes viennent du catalogue
    # (bar, épicerie). Les charges et les loyers n'ont pas d'article : la
    # section se tait alors plutôt que d'afficher une liste d'une ligne.
    def articles(limite: 8)
      @articles ||= ecritures.where.not(catalog_item_id: nil)
                             .joins(:catalog_item)
                             .group("catalog_items.name")
                             .pluck(Arel.sql("catalog_items.name, COALESCE(SUM(account_entries.quantity), 0), " \
                                             "SUM(account_entries.amount_cents)"))
                             .map { |name, qty, cents| Article.new(name: name, quantity: qty.to_f, amount_cents: cents.to_i) }
                             .sort_by { |a| -a.amount_cents }
      @articles.first(limite)
    end

    def reglements
      @reglements ||= ecritures.where(amount_cents: ...0).chronological.to_a
    end

    def outstanding = @outstanding ||= Outstanding.new(@account)

    # Une page vide n'aide personne : elle dit « aucun mouvement », pas « voici
    # zéro euro réparti sur huit canaux ».
    def any? = ecritures.exists?

    private

    def ecritures
      @account.account_entries.where(entry_date: debut..fin)
    end

    def premiere_ecriture
      @premiere_ecriture ||= @account.account_entries.minimum(:entry_date)
    end

    def annees_actives
      @annees_actives ||= begin
        premiere = premiere_ecriture&.year
        premiere ? (premiere..@today.year).to_a : []
      end
    end

    # Un seul aller-retour en base pour les douze colonnes ET la répartition :
    # le regroupement est fait en SQL, la mise en forme en Ruby.
    def depenses_brutes
      @depenses_brutes ||= ecritures.where("amount_cents > 0")
                                    .group(Arel.sql("date_trunc('month', entry_date)::date"), :flow)
                                    .sum(:amount_cents)
    end

    def depenses_par_mois_et_flow
      @depenses_par_mois_et_flow ||= depenses_brutes.each_with_object({}) do |((month, flow), cents), hash|
        (hash[month] ||= Hash.new(0))[flow || "other"] += cents
      end
    end

    def depenses_par_flow
      @depenses_par_flow ||= depenses_brutes.each_with_object(Hash.new(0)) do |((_month, flow), cents), hash|
        hash[flow || "other"] += cents
      end
    end
  end
end
