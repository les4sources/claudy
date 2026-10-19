module Finance
  # Modifier la ventilation d'une ligne déjà affectée (Michael, 2026-10-19) :
  # « j'ai affecté une ligne et j'ai oublié de la ventiler autrement ».
  #
  # Il fallait trois gestes : annuler la passation, retirer chaque affectation,
  # tout ressaisir. Ici, c'est un seul : on corrige les parts sur un écran, et
  # tout passe ensemble ou rien. Une correction à moitié faite laisserait une
  # ligne contre-passée et vide, pire que l'erreur qu'on voulait corriger.
  #
  # Une ligne comptabilisée ne se réécrit pas en place : son écriture est
  # contre-passée (les deux restent lisibles au grand livre), puis la ligne se
  # recomptabilise d'elle-même si les nouvelles parts la couvrent.
  #
  # Une part existante garde ce qu'elle rapproche (facture, séjour, événement,
  # compte d'un habitant) : on change son compte, son pôle, son entité ou son
  # montant, pas sa pièce. Pour changer de pièce, on retire la part.
  class ReallocateCashEntry < ServiceBase
    class Refused < StandardError; end

    Result = Struct.new(:changed, :was_posted, :posted, :remaining_cents, keyword_init: true)

    ATTRIBUTS = %i[general_account_id team_id legal_entity_id amount_cents].freeze

    # `parts` : des hashes `{ id:, general_account_id:, team_id:, legal_entity_id:,
    # amount_cents: }`, dans l'ordre de l'écran ; `id` absent pour une part
    # nouvelle. Une part existante qui n'y figure plus est retirée.
    def initialize(cash_entry:, parts:, whodunnit: nil)
      @entry = cash_entry
      @parts = parts.map { |part| part.to_h.symbolize_keys }
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { cash_entry: @entry.id }) { reallocate }
    end

    def run!
      reallocate
    end

    private

    def reallocate
      ApplicationRecord.transaction do
        @entry.lock!
        garde_fous!

        existantes = @entry.cash_allocations.ordered.to_a
        identiques?(existantes) ? inchange(existantes) : modifier!(existantes)
      end
    end

    def modifier!(existantes)
      controler_total!
      etait_passee = @entry.posted?
      contre_passer! if etait_passee

      appliquer!(existantes.index_by(&:id))
      Shop::ConsignorTransfer.new(cash_entry: @entry.reload).unlink_if_orphan!

      passee = @entry.reload.fully_allocated? && @entry.cash_allocations.exists?
      Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run! if passee

      Result.new(changed: true, was_posted: etait_passee, posted: passee, remaining_cents: @entry.remaining_cents)
    end

    def garde_fous!
      raise Refused, "Cette ligne est exclue : elle n'attend plus d'affectation." if @entry.status == "excluded"

      # Le mois arrêté est une promesse faite au comptable, comme pour la
      # feuille de caisse (`UpdateCashLine`).
      if MonthClosing.closed?(@entry.entry_date)
        raise Refused, "#{I18n.l(@entry.entry_date.beginning_of_month, format: '%B %Y')} est arrêté : " \
                       "la ventilation de cette ligne ne se modifie plus."
      end

      inconnues = @parts.filter_map { |part| part[:id].presence&.to_i } - @entry.cash_allocations.pluck(:id)
      raise Refused, "Une des parts n'appartient pas à cette ligne. Rien n'a été modifié." if inconnues.any?
    end

    # Rien n'a bougé : on ne contre-passe pas pour rien. Deux écritures de plus
    # au grand livre pour un clic sur « Enregistrer » à l'identique, c'est du
    # bruit que le comptable devrait relire.
    def identiques?(existantes)
      avant = existantes.map { |a| [a.id, *ATTRIBUTS.map { |cle| a.public_send(cle) }] }
      apres = @parts.map { |p| [p[:id].presence&.to_i, *ATTRIBUTS.map { |cle| p[cle].presence&.to_i }] }
      avant == apres
    end

    def inchange(existantes)
      Result.new(changed: false, was_posted: @entry.posted?, posted: @entry.posted?,
                 remaining_cents: @entry.amount_cents - existantes.sum(&:amount_cents))
    end

    def controler_total!
      total = @parts.sum { |part| part[:amount_cents].to_i }
      return if total.abs <= @entry.amount_cents.abs

      raise Refused, "Les #{@parts.size} parts font #{Money.new(total, 'EUR').format}, " \
                     "la ligne fait #{Money.new(@entry.amount_cents, 'EUR').format}. Rien n'a été modifié."
    end

    def contre_passer!
      Accounting::UnpostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run!
      @entry.reload
    rescue Accounting::UnpostCashEntry::ClosedFiscalYear => e
      raise Refused, e.message
    end

    # Le garde-fou du modèle (`within_entry_amount`) compare chaque part à
    # celles déjà en base : passer de 300 € + 0 à 200 € + 100 € échouerait si
    # la nouvelle part de 100 € arrivait avant que la première ait diminué.
    # D'où l'ordre : retirer, puis diminuer, puis augmenter, puis créer.
    def appliquer!(existantes)
      gardees = @parts.filter_map { |part| part[:id].presence&.to_i }
      existantes.each_value { |allocation| allocation.destroy! unless gardees.include?(allocation.id) }

      etapes = @parts.each_with_index.map do |part, index|
        allocation = part[:id].present? ? existantes.fetch(part[:id].to_i) : CashAllocation.new(cash_entry: @entry)
        ordre = if allocation.new_record? then 2
                elsif part[:amount_cents].to_i.abs <= allocation.amount_cents.abs then 0
                else 1
                end
        [ordre, index, allocation, part]
      end

      etapes.sort_by { |ordre, index, *| [ordre, index] }.each do |_, index, allocation, part|
        allocation.assign_attributes(part.slice(*ATTRIBUTS))
        next if allocation.save

        raise Refused, "Part #{index + 1} : #{allocation.errors.full_messages.to_sentence}. Rien n'a été modifié."
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      raise Refused, e.record.errors.full_messages.to_sentence
    end
  end
end
