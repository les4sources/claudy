module Finance
  # La file « À affecter » se travaille SANS rechargement (Michael, 2026-09-30).
  #
  # Chaque geste d'affectation redirigeait vers la file : la page repartait du
  # haut, et il fallait redescendre retrouver l'endroit où l'on en était, ligne
  # après ligne. Désormais, un geste fait DEPUIS la file répond en Turbo Stream :
  # la ligne affectée disparaît, une ligne encore incomplète se redessine en
  # place, déroulée, et la fenêtre ne bouge pas.
  #
  # Hors de la file (fiche d'une ligne, requête sans Turbo), rien ne change : la
  # redirection d'avant reste le chemin.
  module UnallocatedQueue
    extend ActiveSupport::Concern

    # Deux fois plus de lignes qu'au départ (Michael, 2026-09-30) : on ne quitte
    # plus la page à chaque geste, on la vide. Le travail reste borné à la page
    # affichée — c'est ce qui compte pour l'issue #202.
    PAR_PAGE = 50

    private

    # Les lignes en attente, restreintes par les filtres de la file : compte
    # ou famille de comptes (epic #250), recherche, période, sens et montant
    # (epic #288, phase 4). Sans filtre, la file entière.
    def file_scope(filtres) = Finance::QueueFilter.new(filtres).scope

    # Le compte artisanat et les artisans, UNE fois pour la page : une ligne
    # affectée à l'artisanat demande à qui revient le virement (epic #359,
    # phase 4), pré-rempli par le mot-clé de la communication.
    def charger_artisans
      @shop_settings = ShopSetting.current
      @consignors = Consignor.ordered.to_a
    end

    # Tout ce qu'une ligne de la file affiche : propositions de rapprochement,
    # suggestion, listes du formulaire. Calculé pour les lignes DONNÉES
    # seulement — la page à l'ouverture, une seule ligne après un geste.
    def charger_pistes(entries)
      @comment_counts = comment_counts(entries)
      charger_artisans

      # Les suggestions se recalculent à l'ouverture de l'écran : c'est le seul
      # moment où elles servent, et ça évite un job de fond que l'application
      # n'a pas les moyens de garantir. Sur les lignes AFFICHÉES seulement — les
      # recalculer toutes coûtait 38 secondes à chaque page.
      Finance::SuggestAllocations.new(cash_entries: entries, whodunnit: current_user&.email).run!
      # Jev, lui, ne se demande pas ici : chaque ligne sans règle charge sa
      # proposition dans son propre cadre (`suggestion`), en parallèle.
      @jev_enabled = Jev::Client.new.configured?

      # Le rapprochement de séjour se calcule à l'affichage : il dépend de
      # l'état des soldes, qui bouge à chaque paiement.
      # Les séjours ouverts et leurs soldes, calculés UNE fois pour la page.
      stays, soldes = Finance::MatchStay.prechargement(entries)

      @stay_matches = entries.each_with_object({}) do |entry, hash|
        next if entry.cash_allocations.any?

        correspondance = Finance::MatchStay.new(cash_entry: entry, open_stays: stays, soldes: soldes).run!
        next if correspondance.nil?

        lignes = begin
          Finance::VentilateStay.new(stay: correspondance.stay, amount_cents: entry.amount_cents).run!
        rescue Finance::VentilateStay::EmptyQuote, Finance::VentilateStay::MissingMapping
          nil
        end
        next if lignes.blank?

        hash[entry.id] = { match: correspondance, lines: lignes }
      end
      # Les virements aux membres (epic #246, phase 2) : une ligne sortante peut
      # solder le compte créditeur d'un cuisinier. Les soldes se calculent UNE
      # fois pour la page — les recalculer ligne à ligne est ce qui avait fait
      # tomber cet écran à l'issue #202.
      @payout_matches = Finance::MatchMemberPayouts.new.for_entries(entries)
      # Les factures d'achat à payer (epic #240, phase 4) : une ligne sortante
      # dont le montant ou l'IBAN correspond à une facture `to_pay`. Les
      # factures sont chargées UNE fois pour la page, comme les soldes.
      @invoice_matches = Finance::MatchPurchaseInvoices.new.for_entries(entries)
      # Les notes de frais et de mission à payer (epic #241, phase 3) : même
      # geste que la facture, sur une autre dette. Les notes `processing` sont
      # chargées UNE fois pour la page, comme les factures.
      @expense_report_matches = Finance::MatchExpenseReports.new.for_entries(entries)
      # Les versements Stripe (epic #250, phase 2) : une ligne bancaire ENTRANTE
      # dont le montant et la date correspondent à un versement pas encore
      # rapproché. Les versements sont chargés UNE fois pour la page.
      @stripe_matches = Finance::MatchStripePayouts.new.for_entries(entries)
      # Les factures de VENTE (epic #240, phase 6) : une ligne ENTRANTE du
      # montant exact d'une facture émise, ou venant de l'IBAN déjà appris pour
      # ce client. Les factures sont chargées UNE fois pour la page.
      @sales_invoice_matches = Finance::MatchSalesInvoices.new.for_entries(entries)
      # Les règlements des habitants (issue #349) : le miroir des virements
      # ci-dessus. Une ligne ENTRANTE peut éteindre la dette d'un ménage ou
      # d'une personne. Les soldes débiteurs sont chargés UNE fois pour la page.
      @settlement_matches = Finance::MatchMemberSettlements.new.for_entries(entries)

      @general_accounts = GeneralAccount.actives.ordered
      @teams = Team.ordered
      @entities = LegalEntity.actives.ordered
      @events = recent_events
    end

    # { cash_entry_id => nombre de commentaires } pour les lignes de la page,
    # en une requête : le badge ne doit pas coûter une requête par ligne.
    def comment_counts(entries)
      Comment.where(commentable_type: "CashEntry", commentable_id: entries.map(&:id))
             .group(:commentable_id).count
    end

    # Les événements proposables au rattachement d'une recette (epic #245,
    # phase 2) : dix-huit mois en arrière et l'avenir. Au-delà, la liste devient
    # une roue interminable pour retrouver un stage de 2023 que plus personne
    # n'encaisse.
    def recent_events
      Event.where("starts_at >= ?", 18.months.ago).order(starts_at: :desc)
    end

    # Le geste vient-il de la file, par Turbo ? C'est la page d'où part le
    # formulaire qui le dit : les boutons de rapprochement ne portent aucun
    # paramètre qui l'annonce.
    def depuis_la_file?
      request.format.turbo_stream? && referer_uri&.path == finance_unallocated_cash_entries_path
    end

    def referer_uri
      request.referer.present? ? URI.parse(request.referer) : nil
    rescue URI::InvalidURIError
      nil
    end

    # Après un geste sur `entry` : réponse en place si le geste vient de la
    # file, redirection vers `ailleurs` sinon.
    def apres_affectation(entry, ailleurs, notice: nil, alert: nil)
      if depuis_la_file?
        repondre_dans_la_file(entry, notice: notice, alert: alert)
      else
        redirect_to ailleurs, notice: notice, alert: alert
      end
    end

    # La ligne sort de la file si elle n'y est plus ; sinon elle se redessine
    # déroulée, avec l'éventuel refus écrit DANS la ligne — la bannière du haut
    # est hors de vue quand on travaille en bas de page.
    def repondre_dans_la_file(entry, notice: nil, alert: nil)
      entry = CashEntry.includes(:cash_account, :cash_allocations, :allocation_suggestions).find(entry.id)
      # Le compteur suit les filtres de la page d'où part le geste : dans une
      # vue filtrée, il compte ce qui reste À CET ENDROIT, pas toute la file.
      filtres = Rack::Utils.parse_nested_query(referer_uri&.query.to_s)
      en_attente = file_scope(filtres).count

      flash.now[:notice] = notice if notice
      flash.now[:alert] = alert if alert

      streams = [
        turbo_stream.replace("messages", partial: "layouts/components/messages"),
        turbo_stream.update("file-compteur", "#{en_attente} ligne(s) en attente"),
        turbo_stream.update("file-compteur-filtre", "#{en_attente} ligne(s) sur #{CashEntry.pending.count} en attente.")
      ]
      if entry.status == "pending"
        charger_pistes([entry])
        streams << turbo_stream.replace("file-ligne-#{entry.id}",
                                        partial: "finance/cash_entries/queue_entry",
                                        locals: { entry: entry, ouvert: true, erreur: alert })
      else
        streams << turbo_stream.remove("file-ligne-#{entry.id}")
      end

      render turbo_stream: streams
    end
  end
end
