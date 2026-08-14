module Api
  module V1
    # Fiches papier et encodage matriciel (#158).
    #
    # L'encodage passe par Finance::EncodePaperSheet, le MÊME service que l'écran
    # d'encodage. On hérite donc de ses trois propriétés sans les réécrire : une
    # clé d'idempotence par cellule (rejouer met à jour, ne duplique pas), une
    # cellule vidée supprime son écriture, et une écriture rattachée à un
    # décompte émis n'est ni modifiée ni supprimée — elle est signalée.
    #
    # POST est un UPSERT sur le couple (mois, canal) : il n'existe qu'une fiche
    # de bar pour juillet 2026, la reposter la retrouve.
    class PaperSheetsController < BaseController
      before_action :get_sheet, only: [:show, :update, :encode]

      def index
        scope = PaperSheet.recent_first
        scope = scope.where(channel: params[:channel]) if params[:channel].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        if params[:period_month].present?
          scope = scope.where(period_month: params[:period_month].to_date.beginning_of_month)
        end

        @paper_sheets = paginate(scope)
      end

      def show
        load_totals
      end

      def create
        attributes = sheet_params
        month = attributes[:period_month].presence&.to_date&.beginning_of_month

        @paper_sheet = PaperSheet.find_or_initialize_by(period_month: month, channel: attributes[:channel])
        @created = @paper_sheet.new_record?

        if @paper_sheet.update(attributes)
          load_totals
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@paper_sheet)
        end
      end

      def update
        if @paper_sheet.update(sheet_params)
          load_totals
          render :show
        else
          render_invalid(@paper_sheet)
        end
      end

      # POST /api/v1/paper_sheets/:id/encode
      #   { "entry_mode": "quantity",
      #     "cells": { "<member_account_id>": { "<catalog_item_id>": 3 } } }
      #
      # Les cellules sont adressées par IDENTIFIANT, jamais par nom : encoder la
      # consommation d'un ménage sur le compte d'un autre est la seule erreur
      # vraiment coûteuse ici, et une correspondance approximative n'a rien à
      # faire sur un chemin d'écriture. Passer par /member_accounts?q= et
      # /catalog_items?q= pour résoudre les noms d'abord.
      def encode
        cells = params.require(:cells).to_unsafe_h

        @report = Finance::EncodePaperSheet.new(
          sheet: @paper_sheet,
          cells: cells,
          entry_mode: params[:entry_mode],
          whodunnit: "api:agent"
        ).run!

        @paper_sheet.reload
        load_totals
        render :show
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record)
      end

      private

      def get_sheet
        @paper_sheet = PaperSheet.find(params[:id])
      end

      # Totaux par compte : c'est ce qui permet de vérifier un encodage sans
      # relire les écritures une par une.
      def load_totals
        sums = @paper_sheet.account_entries.group(:member_account_id).sum(:amount_cents)
        counts = @paper_sheet.account_entries.group(:member_account_id).count
        accounts = MemberAccount.where(id: sums.keys).index_by(&:id)

        @totals = sums.map do |account_id, cents|
          { account: accounts[account_id], cents: cents, entries: counts[account_id].to_i }
        end.sort_by { |line| -line[:cents] }
      end

      def sheet_params
        params.require(:paper_sheet).permit(:period_month, :channel, :status, :entry_mode,
                                            :member_account_id, :notes)
      end
    end
  end
end
