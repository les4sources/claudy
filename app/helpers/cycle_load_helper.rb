module CycleLoadHelper
  WEEKLY_CAPACITY = 16.0

  # Returns a hash describing one person's load against the cycle capacity.
  #   engaged: engaged active hours (excluding :reportee)
  #   available: 16h × cycle weeks (0 if no cycle)
  #   ratio: engaged / available (0 if no cycle)
  #   state: :ok | :tight (>85%) | :overload (>100%) | :idle (<30%)
  #   accent: tailwind color stem ("teal" | "amber" | "rose")
  def cycle_load_for(engaged:, cycle:)
    engaged = engaged.to_f
    weeks_total = cycle ? ((cycle.end_date - cycle.start_date).to_i + 1) / 7.0 : 0
    available = (weeks_total * WEEKLY_CAPACITY).round(1)
    ratio = available > 0 ? (engaged / available) : 0
    state =
      if available <= 0 then :ok
      elsif ratio > 1 then :overload
      elsif ratio > 0.85 then :tight
      elsif ratio < 0.3 then :idle
      else :ok
      end
    accent = case state
             when :overload then "rose"
             when :tight then "amber"
             else "teal"
             end
    {
      engaged: engaged,
      available: available,
      ratio: ratio,
      pct: (ratio * 100).round,
      meter_pct: (ratio * 100).clamp(0, 100),
      state: state,
      accent: accent,
    }
  end

  # Computes the weekly pace required to consume remaining hours
  # before the cycle ends. Returns 0 if no cycle or no time left.
  def cycle_weekly_pace(engaged:, cycle:, completed_hours: 0)
    return 0 unless cycle
    remaining_days = [(cycle.end_date - Date.today).to_i, 0].max
    weeks_remaining = remaining_days / 7.0
    return 0 if weeks_remaining <= 0
    remaining_hours = [engaged.to_f - completed_hours.to_f, 0].max
    remaining_hours / weeks_remaining
  end
end
