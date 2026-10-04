module Finance
  # Les affectations d'une ligne de trésorerie. Une allocation ne naît que d'un
  # geste humain : il n'existe aucun compte par défaut, aucune règle qui affecte
  # d'office. C'est le défaut de Winbooks éliminé par le schéma.
  class CashAllocationsController < Finance::AccountingBaseController
    include Finance::UnallocatedQueue

    before_action :get_entry

    # Le verrou sérialise les affectations concurrentes : deux saisies
    # simultanées liraient sinon le même solde restant et passeraient toutes les
    # deux le contrôle de couverture, créant de l'argent qui n'existe pas.
    #
    # Une ligne peut se répartir en PLUSIEURS parts d'un coup (epic #288,
    # phase 6) : une nuitée et des consommations au bar, une salle et un repas.
    # Les parts s'enregistrent ensemble ou pas du tout — un découpage à moitié
    # posé est pire qu'un découpage refusé. Le cas simple (une seule part,
    # `cash_allocation`) passe par le même chemin.
    def create
      allocations = []
      erreur = nil

      @entry.with_lock do
        # `CashAllocation.new` plutôt que `@entry.cash_allocations.new` : une
        # part refusée ne doit pas rester dans l'association et se voir
        # « déjà affectée » quand la ligne se redessine avec son erreur.
        allocations = parts_params.map { |attrs| CashAllocation.new(attrs.merge(cash_entry: @entry)) }
        erreur = depassement(allocations)
        next if erreur

        ActiveRecord::Base.transaction(requires_new: true) do
          allocations.each_with_index do |allocation, index|
            next if allocation.save

            erreur = message_de_part(allocation, index, allocations.size)
            raise ActiveRecord::Rollback
          end
        end
      end

      if erreur.nil?
        allocations.each { |allocation| link_consignor(allocation) }
        maybe_post
      else
        apres_affectation(@entry.reload, redirect_target, alert: erreur)
      end
    end

    def destroy
      allocation = @entry.cash_allocations.find(params[:id])

      if allocation.destroy
        Shop::ConsignorTransfer.new(cash_entry: @entry.reload).unlink_if_orphan!
        redirect_to redirect_target, notice: "Affectation retirée."
      else
        redirect_to redirect_target, alert: allocation.errors.full_messages.to_sentence
      end
    end

    private

    def get_entry = @entry = CashEntry.find(params[:cash_entry_id])

    # Une affectation au compte artisanat dit À QUI revient le virement (epic
    # #359, phase 4) : l'artisan choisi dans le formulaire, pré-rempli par le
    # mot-clé. Vers un autre compte, le champ est ignoré.
    def link_consignor(allocation)
      transfer = Shop::ConsignorTransfer.new(cash_entry: @entry)
      return unless transfer.craft_allocation?(allocation.general_account_id)

      transfer.link!(Consignor.find_by(id: params[:consignor_id].presence))
    end

    # Une ligne entièrement affectée se comptabilise dans la foulée : demander
    # un second clic pour un geste qui n'a plus aucune décision à prendre, c'est
    # la meilleure façon de laisser des lignes affectées mais non passées.
    def maybe_post
      unless @entry.reload.fully_allocated?
        return apres_affectation(@entry, redirect_target,
                                 notice: "Affectation enregistrée — il reste #{Money.new(@entry.remaining_cents, 'EUR').format} à affecter.")
      end

      Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: current_user&.email).run!
      apres_affectation(@entry, redirect_target, notice: "Ligne entièrement affectée et comptabilisée.")
    rescue Accounting::PostDocument::MissingFiscalYear => e
      apres_affectation(@entry, redirect_target,
                        alert: "Affectation enregistrée, mais la ligne n'a pas pu être comptabilisée : #{e.message}")
    end

    def redirect_target
      params[:from_unallocated].present? ? finance_unallocated_cash_entries_path : finance_cash_entry_path(@entry)
    end

    # La première part arrive sous `cash_allocation` — c'est le formulaire de
    # toujours — et les suivantes sous `parts[n]`, ajoutées dans la file.
    def parts_params
      premiere = params.require(:cash_allocation)
      suivantes = params[:parts].respond_to?(:values) ? params[:parts].values : []
      [premiere, *suivantes].map { |part| part_attributes(part) }
    end

    def part_attributes(part)
      permitted = part.permit(:general_account_id, :analytic_account_id, :team_id,
                              :legal_entity_id, :label, :amount, :event_id)
      amount = permitted.delete(:amount)
      permitted[:amount_cents] = Monetize.parse(amount.to_s).cents if amount.present?

      # L'événement devient le `document` de l'allocation (epic #245, phase 2).
      # On ne pose PAS le couple polymorphe depuis les paramètres : `document_type`
      # soumis par le client laisserait choisir la classe à instancier.
      event_id = permitted.delete(:event_id)
      permitted[:document] = Event.find_by(id: event_id) if event_id.present?
      permitted
    end

    # La somme des parts se contrôle AVANT d'en enregistrer une seule. Le
    # garde-fou du modèle (`within_entry_amount`) ne voit qu'une part à la fois :
    # sur la troisième, il dirait « il ne reste que 20 € », ce qui laisse croire
    # que les deux premières sont passées.
    def depassement(allocations)
      return nil if allocations.size < 2

      total = allocations.sum { |a| a.amount_cents.to_i }
      reste = @entry.remaining_cents
      return nil if total.abs <= reste.abs

      "Les #{allocations.size} parts font #{Money.new(total, 'EUR').format}, " \
        "il ne reste que #{Money.new(reste, 'EUR').format} à affecter. Rien n'a été enregistré."
    end

    def message_de_part(allocation, index, total)
      message = allocation.errors.full_messages.to_sentence
      return message if total == 1

      "Part #{index + 1} : #{message}. Rien n'a été enregistré."
    end
  end
end
