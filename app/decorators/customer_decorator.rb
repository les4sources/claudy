class CustomerDecorator < ApplicationDecorator
  delegate_all

  # Use the paginating collection decorator so will_paginate keeps working on
  # the decorated index collection (same pattern as BookingDecorator).
  def self.collection_decorator_class
    PaginatingDecorator
  end

  def type_label
    organization? ? "Organisation" : "Particulier"
  end

  def type_badge
    klass = organization? ? "bg-indigo-100 text-indigo-800" : "bg-gray-100 text-gray-800"
    h.content_tag(:span, type_label,
                  class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{klass}")
  end

  def catch_all_badge
    return unless catch_all?
    h.content_tag(:span, "Fourre-tout migration",
                  class: "inline-flex items-center rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-medium text-amber-800")
  end

  def display_name
    name.presence || email
  end

  def language_label
    { "fr" => "Français", "nl" => "Nederlands", "en" => "English" }.fetch(language, language)
  end

  def upcoming_stays
    stays.current_and_future
  end

  # Compteurs de la liste : lus depuis les colonnes calculées par
  # `Customer.with_stay_counts` (aucun N+1). Repli sur une requête si le
  # décorateur est utilisé hors de ce scope (ex. page show).
  def stays_count
    if object.has_attribute?(:stays_count)
      object.stays_count.to_i
    else
      object.stays.count
    end
  end

  def upcoming_stays_count
    if object.has_attribute?(:upcoming_stays_count)
      object.upcoming_stays_count.to_i
    else
      object.stays.current_and_future.count
    end
  end

  def past_stays
    stays.past
  end

  def total_paid
    Money.new(payments.paid.sum(:amount_cents), "EUR").format
  end
end
