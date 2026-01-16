
#import "Basic";
#import "Random";

main :: () {
    start_date: Calendar_Time;
    start_date.year                       = cast(s32) (random_get() % 200) + 1970;
    start_date.month_starting_at_0        = cast(s8)  (random_get() % 12);
    start_date.day_of_month_starting_at_0 = cast(s8)  (random_get() % 28);
    start_date.hour                       = cast(s8)  (random_get() % 24);
    start_date.minute                     = cast(s8)  (random_get() % 60);
    start_date.second                     = cast(s8)  (random_get() % 60);
    start_date.millisecond                = cast(s16) (random_get() % 1000);
    calendar_to_apollo(start_date);

    dates := NewArray(10_000_000, Calendar_Time);

    // Generate random dates.
    for* dates {
        it.year                       = cast(s32) (random_get() % 200) + 1970;
        it.month_starting_at_0        = cast(s8)  (random_get() % 12);
        it.day_of_month_starting_at_0 = cast(s8)  (random_get() % 28);
        it.hour                       = cast(s8)  (random_get() % 24);
        it.minute                     = cast(s8)  (random_get() % 60);
        it.second                     = cast(s8)  (random_get() % 60);
        it.millisecond                = cast(s16) (random_get() % 1000);
    }
    apollo_dates := NewArray(dates.count, Apollo_Time);
    for* apollo_dates it.* = native_calendar_to_apollo(dates[it_index]);

    results := NewArray(dates.count, Apollo_Time);

    native_start := current_time_monotonic();
    for* results {
        it.* = native_calendar_to_apollo(dates[it_index]);
    }
    native_end := current_time_monotonic();

    results = NewArray(dates.count, Apollo_Time);

    system_start := current_time_monotonic();
    for* results {
        it.* = calendar_to_apollo(dates[it_index]);
    }
    system_end := current_time_monotonic();


    log("Native time: %s\nSystem time: %s",
        to_float64_seconds(native_end - native_start),
        to_float64_seconds(system_end - system_start));
}









native_apollo_to_calendar :: (apollo: Apollo_Time) -> Calendar_Time {

    // Apollo Time for March 1st 2000
    LEAPOCH :: Apollo_Time.{14200603904491421696, 52369};

    DAYS_PER_QUATERCENTENARY :: 146097;
    DAYS_PER_CENTURY         :: 36524;
    DAYS_PER_QUADRENNIUM     :: 1461;

    seconds := to_seconds(apollo - LEAPOCH);

    // Convert seconds back to Apollo to get the value rounded down to the nearest second. Is there a way to simplify this.
    milliseconds := to_milliseconds(apollo - seconds_to_apollo(seconds) - LEAPOCH);
    if milliseconds < 0 {
        milliseconds += 1000;
        seconds -= 1;
    }

    days := seconds / 86400;
    seconds %= 86400;

    if seconds < 0 {
        seconds += 86400;
        days -= 1;
    }

    weekday := (days + 3) % 7;
    if weekday < 0 weekday += 7;

    quad_centuries := days / DAYS_PER_QUATERCENTENARY;
    days %= DAYS_PER_QUATERCENTENARY;

    if days < 0 {
        days += DAYS_PER_QUATERCENTENARY;
        quad_centuries -= 1;
    }

    centuries := days / DAYS_PER_CENTURY;
    if centuries == 4 centuries -= 1;
    days -= centuries * DAYS_PER_CENTURY;

    quadrennia := days / DAYS_PER_QUADRENNIUM;
    if quadrennia == 25 quadrennia -= 1;
    days -= quadrennia * DAYS_PER_QUADRENNIUM;

    years := days / 365;
    if years == 4 years -= 1;
    days -= years * 365;

    years += 4*quadrennia + 100*centuries + 400*quad_centuries;

    days_in_month :: int.[ 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 29 ];
    months := 0;

    while days_in_month[months] <= days {
        days -= days_in_month[months];
        months += 1;
    }

    if months >= 10 {
        months -= 12;
        years += 1;
    }

    ct: Calendar_Time;

    ct.month\      _starting_at_0 = cast(s8, months + 2);
    ct.day_of_month_starting_at_0 = cast(s8, days);
    ct.day_of_week\_starting_at_0 = cast(s8, weekday);

    ct.year        = cast(s32, years + 2000);
    ct.hour        = cast(s8,  seconds / 3600);
    ct.minute      = cast(s8, (seconds / 60) % 60);
    ct.second      = cast(s8,  seconds % 60);
    ct.millisecond = cast(s16, milliseconds);

    return ct;
}

native_calendar_to_apollo :: (ct: Calendar_Time) -> Apollo_Time {
    // Todo: Doesn't work with dates before 1 AD. It doesn't seem to work on Linux either, but I feel like it should definitely be made to work.

    // We calculate Apollo Time relative to 1.1.1970 and then add the offset at the end, to make everything easier to think about.
    LEAP_YEARS_BEFORE_1970 :: 477;

    last_year := cast(s64) ct.year - 1;
    leap_years_before := last_year/4 - last_year/100 + last_year/400;

    leap_year_count := leap_years_before - LEAP_YEARS_BEFORE_1970;

    year_difference := cast(s64) ct.year - 1970;

    seconds := 31536000 * (year_difference - leap_year_count);
    seconds += 31622400 * leap_year_count;

    cumulative_days :: int.[
        0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365
    ];

    seconds += cumulative_days[ct.month_starting_at_0] * 86400;

    is_leap_year := (ct.year % 4 == 0) && ((ct.year % 100 != 0) || (ct.year % 400 == 0));

    if ct.month_starting_at_0 > 1 && is_leap_year {
        seconds += 86400;
    }

    seconds += cast(int) ct.day_of_month_starting_at_0 * 86400;
    seconds += cast(int) ct.hour * 60 * 60;
    seconds += cast(int) ct.minute * 60;
    seconds += cast(int) ct.second;

    apollo := seconds_to_apollo(seconds);
    apollo += milliseconds_to_apollo(ct.millisecond);
    apollo += APOLLO_TIME_FOR_JAN_1_1970;

    return apollo;
}
