
get_kernel_timestamp :: () -> Apollo_Time {

    // This method of converting TSC to Apollo Time is not precise for low TSC frequencies, like those you get from QEMU when virtualization is not enabled.
    // Use the higher-latency, more complicated HPET timer.
    if global.tsc_frequency < 1_000_000 {
        return hpet_get_monotonic_time();
    }

    timestamp: Apollo_Time;
    timestamp.low = rdtsc();

    FEMTOSECONDS_PER_SECOND :: 1_000_000_000_000_000;
    timestamp *= FEMTOSECONDS_PER_SECOND;
    timestamp /= cast(s64) global.tsc_frequency;

    return timestamp;
}

get_monotonic_system_time :: () -> Apollo_Time {
    return get_kernel_timestamp() + global.boot_time;
}

get_monotonic_time :: get_monotonic_system_time;

native_calendar_to_apollo :: (ct: Calendar_Time) -> Apollo_Time {
    // Todo: Doesn't work with dates before 1 AD. That doesn't seem to work on Linux either, but it should definitely be made to work.

    // Calculate Apollo Time relative to 1.1.1970 and then add the offset at the end, to make everything easier to think about.
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

// Ported from MUSL libc
// https://git.musl-libc.org/cgit/musl/tree/src/time/__secs_to_tm.c

native_apollo_to_calendar :: (apollo: Apollo_Time) -> Calendar_Time {

    // Apollo Time for March 1st 2000
    LEAPOCH :: Apollo_Time.{14200603904491421696, 52369};

    DAYS_PER_QUATERCENTENARY :: 146097;
    DAYS_PER_CENTURY         :: 36524;
    DAYS_PER_QUADRENNIUM     :: 1461;

    seconds := to_seconds(apollo - LEAPOCH);

    // Convert seconds back to Apollo to get the value rounded down to the nearest second. Maybe there's a way to simplify this.
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


busy_wait :: (microseconds: s64) {
    start := get_kernel_timestamp();
    end   := start + microseconds_to_apollo(microseconds);

    assert(end >= start);

    while get_kernel_timestamp() < end #asm {
        pause;
    }
}


// CMOS Real Time Clock (RTC)

Rtc_Port :: enum u16 {
    ADDRESS :: 0x70;
    DATA    :: 0x71;
}

Rtc_Register :: enum u8 {
    SECONDS          :: 0x00;
    SECONDS_ALARM    :: 0x01;
    MINUTES          :: 0x02;
    MINUTES_ALARM    :: 0x03;
    HOURS            :: 0x04;
    HOURS_ALARM      :: 0x05;
    WEEKDAY          :: 0x06;
    DAY_OF_THE_MONTH :: 0x07;
    MONTH            :: 0x08;
    YEAR             :: 0x09;
    STATUS_A         :: 0x0a;
    STATUS_B         :: 0x0b;
    STATUS_C         :: 0x0c;

    // CENTURY may be somewhere here, as described by ACPI
}

rtc_init :: () {
    _24H_CLOCK : u8 : 0x2;
    BCD_MODE   : u8 : 0x4;

    status := rtc_read(.STATUS_B);
    status |= _24H_CLOCK;
    rtc_write(.STATUS_B, status);

    global.rtc_format_is_bcd = status & BCD_MODE == 0;
}

#program_export
rtc_initial_interrupt :: () {
    write_string("====== RTC interrupt ======\n");
} @InterruptRoutine

rtc_read :: (register: Rtc_Register) -> u8 {
    using Rtc_Port;

    ax := cast(u8) register;
    #asm {
        ax === a;
        out.b ADDRESS, ax;
        in.b ax, DATA;
    }

    is_status_register := (register == .STATUS_A)
                       || (register == .STATUS_B)
                       || (register == .STATUS_C);

    if global.rtc_format_is_bcd && !is_status_register {
        ax = (ax & 0xf) + (ax / 16) * 10;
    }

    return ax;
}

rtc_write :: (register: Rtc_Register, value: u8) {
    using Rtc_Port;

    ax := cast(u8) register;
    #asm {
        ax === a;
        out.b ADDRESS, ax;
        mov.b ax, value;
        out.b DATA, ax;
    }
}

rtc_get_calendar_time :: () -> Calendar_Time {
    cal: Calendar_Time;
    cal.time_zone = .UTC;

    cal.month\      _starting_at_0 = cast(s8) rtc_read(.MONTH) - 1;
    cal.day_of_month_starting_at_0 = cast(s8) rtc_read(.DAY_OF_THE_MONTH) - 1;
    cal.day_of_week\_starting_at_0 = cast(s8) rtc_read(.WEEKDAY) - 1;

    cal.year   = cast(s32) rtc_read(.YEAR);
    cal.hour   = cast(s8)  rtc_read(.HOURS);
    cal.minute = cast(s8)  rtc_read(.MINUTES);
    cal.second = cast(s8)  rtc_read(.SECONDS);

    fadt := global.fadt;

    if fadt && fadt.century {
        century := cast(s32) rtc_read(cast(Rtc_Register) fadt.century);
        cal.year += century * 100;
    } else {
        cal.year += 2000;
    }

    return cal;
}



// High precision event timer (HPET)

Hpet_Acpi_Table :: struct {
    #as header: Acpi_Table_Header;
    hardware_revision: u8;
    flags: u8;
    vendor: u16;
    address_space: enum u8 { MAIN_MEMORY :: 0; IO :: 1; };
    stuff: [3] u8;
    base_address: u64 #align 1;
}

Hpet_Register :: enum u64 {
    CAPABILITIES :: 0x0;
    CONFIG       :: 0x10;
    STATUS       :: 0x20;
    COUNTER      :: 0xf0;

    TIMER0       :: 0x100;
    TIMER0_COMP  :: 0x108;
    TIMER1       :: 0x120;
    TIMER1_COMP  :: 0x128;
    TIMER2       :: 0x140;
    TIMER2_COMP  :: 0x148;
}

read :: (reg: Hpet_Register) -> u64 #no_context {
    return cast(*u64, global.high_precision_timer.base_address + cast(u64) reg).*;
}

write :: (reg: Hpet_Register, value: u64) #no_context {
    cast(*u64, global.high_precision_timer.base_address + cast(u64) reg).* = value;
}

Hpet_Config_Flags :: enum_flags u64 {
    ENABLE         :: 0x1;
    LEGACY_ROUTING :: 0x2;
}

Hpet_Capability_Flags :: enum_flags u64 {
    SIXTYFOUR_BIT_COUNTER :: 0x2000;
    LEGACY_ROUTING        :: 0x8000;
}

Hpet_Timer_Flags :: enum_flags u64 {
    INTERRUPT_TYPE           :: 0x2;  // (0=edge  1=level)
    INTERRUPT_ENABLE         :: 0x4;
    PERIODIC_ENABLE          :: 0x8;
    PERIODIC_CAPABLE         :: 0x10;
    SIXTYFOUR_BIT_CAPABLE    :: 0x20;
    WRITE_ACCUMULATOR_ENABLE :: 0x40;
}

HPET :: struct {
    base_address: *void;
    tick_period_femtoseconds: u64;
    counters_are_64_bit: bool;

    Timer :: struct {
        counter: u64;
        counter_is_64_bit: bool;

        ticks_per_interrupt: u64;
        ticks_at_last_interrupt: u64;
    }

    timers: [3] Timer;

    seq_lock: Sequence_Lock;
}

initialize_hpet :: () {
    hpet := *global.high_precision_timer;

    acpi_header := find_acpi_table("HPET");

    if acpi_header == null {
        log_error("HPET is not available");
        bluescreen();
    }

    acpi_table := cast(*Hpet_Acpi_Table) acpi_header;
    assert(acpi_table.address_space == .MAIN_MEMORY);

    virtual := alloc_block(*global.virtual_block_allocator, 4096); // Allocating an individual page using the block allocator because we don't have anything better for virtual memory yet
    map_page(virtual, acpi_table.base_address, .READ_WRITE | .PRESENT | .CACHE_DISABLE);

    offset_in_page := acpi_table.base_address % 0x1000;
    hpet.base_address = xx (virtual + offset_in_page);

    capabilities := cast(Hpet_Capability_Flags) read(Hpet_Register.CAPABILITIES);

    if !(capabilities & .LEGACY_ROUTING) {
        log_error("HPET does not support legacy replacement route");
        bluescreen();
    }

    hpet.counters_are_64_bit = capabilities & .SIXTYFOUR_BIT_COUNTER > 0;
    hpet.tick_period_femtoseconds = cast(u64, capabilities >> 32);

    write(.CONFIG, read(.CONFIG) | cast(u64) Hpet_Config_Flags.LEGACY_ROUTING);

    hpet_restart();

    // Interrupt routing

    t0_gate := cast(u32) allocate_interrupt_gate();
    t1_gate := cast(u32) allocate_interrupt_gate();

    register_interrupt_gate(isr__hpet_timer0_interrupt, t0_gate);
    register_interrupt_gate(isr__hpet_timer1_interrupt, t1_gate);

    // Get INTI2/8 redirection entry. The numbers 2 and 8 come from the legacy replacement routing.
    // Todo: need to detect if there is an interrupt source override in the MADT.
    ioapic_add_interrupt_redirection_table_entry(2, t0_gate);
    ioapic_add_interrupt_redirection_table_entry(8, t1_gate);
}

hpet_configure_timer :: (timer_index: int, frequency: u64, periodic: bool, frequency_in_millihertz := false) {
    assert(timer_index == 0 || timer_index == 1);

    hpet := *global.high_precision_timer;

    register_offset := cast(Hpet_Register, 0x20 * timer_index);

    timer_flags := cast(Hpet_Timer_Flags) read(register_offset + .TIMER0);

    if !(timer_flags & .PERIODIC_CAPABLE) {
        log("HPET timer % is not periodic capable", timer_index);
    }

    if !(timer_flags & .SIXTYFOUR_BIT_CAPABLE) {
        log("HPET timer % is not 64bit capable", timer_index);
    }

    timer_flags |=  (.INTERRUPT_ENABLE | .WRITE_ACCUMULATOR_ENABLE);
    timer_flags &= ~ .INTERRUPT_TYPE;

    if periodic  timer_flags |=  .PERIODIC_ENABLE;
    else         timer_flags &= ~.PERIODIC_ENABLE;

    write(register_offset + .TIMER0, cast(u64) timer_flags);

    timer := *hpet.timers[timer_index];

    ticks_per_second := cast(u64) 1_000_000_000_000_000 / hpet.tick_period_femtoseconds;
    timer.ticks_per_interrupt = ticks_per_second / frequency;

    if frequency_in_millihertz {
        timer.ticks_per_interrupt *= 1000;
    }

    if !periodic {
        timer.ticks_per_interrupt += read(Hpet_Register.COUNTER);
    }
    write(register_offset + .TIMER0_COMP, timer.ticks_per_interrupt);

    timer.counter = 0;
}

hpet_restart :: () {
    config := read(Hpet_Register.CONFIG);

    ENABLE_BIT :: cast(u64) Hpet_Config_Flags.ENABLE;

    write(.CONFIG, config & ~ENABLE_BIT);
    write(Hpet_Register.COUNTER, 0);
    write(.CONFIG, config | ENABLE_BIT);
}

#program_export
hpet_timer0_interrupt :: (data: *Interrupt_Stack_Frame()) #c_call {
    using global.high_precision_timer;

    sequence_write(*seq_lock, #code {
        timers[0].counter += 1;
        timers[0].ticks_at_last_interrupt = read(.COUNTER);
    });

    write_apic_register(.EOI__END_OF_INTERRUPT, 0);
} @InterruptRoutine

#program_export
hpet_timer1_interrupt :: (data: *Interrupt_Stack_Frame()) #c_call {
    using global.high_precision_timer;
    timers[1].counter += 1;
    write_apic_register(.EOI__END_OF_INTERRUPT, 0);
} @InterruptRoutine

hpet_get_monotonic_time :: () -> Apollo_Time {
    using global;

    counter, ticks: u64;

    sequence_read(*high_precision_timer.seq_lock, #code {
        // This could also just use 16-byte compare exchange instead of a seqlock

        counter = high_precision_timer.timers[0].counter;
        ticks   = high_precision_timer.timers[0].ticks_at_last_interrupt;
    });

    // Apparently reading this register can have high latency
    ticks_now := cast(u64) read(.COUNTER);

    if ticks_now < ticks {
        counter_max: u64 = 0xffff_ffff;
        if high_precision_timer.timers[0].counter_is_64_bit {
            counter_max = 0xffff_ffff_ffff_ffff;
        }

        ticks = ticks_now + (counter_max - ticks);
    } else {
        ticks = ticks_now - ticks;
    }

    time_represented_by_ticks: Apollo_Time;
    time_represented_by_ticks.low = cast(u64) ticks;
    time_represented_by_ticks *= cast(s64) high_precision_timer.tick_period_femtoseconds;

    FEMTOSECONDS_PER_MILLISECOND :: 1_000_000_000_000;
    time_represented_by_counter: Apollo_Time;
    time_represented_by_counter.low = counter;
    time_represented_by_counter *= 100 * FEMTOSECONDS_PER_MILLISECOND;

    return time_represented_by_counter + time_represented_by_ticks;
}



Apic_Lvt_Timer :: enum u32 {
    gate_index      :: 8;
    reserved_0      :: 4;
    delivery_status :: 1;
    reserved_1      :: 3;
    mask            :: 1;
    timer_mode      :: 2;
    reserved_2      :: 13;
} @Bitfield

APIC_TIMER_MODE_ONE_SHOT     :: 0b00;
APIC_TIMER_MODE_PERIODIC     :: 0b01;
APIC_TIMER_MODE_TSC_DEADLINE :: 0b10;

configure_apic_timer_interrupt :: (period_in_ticks: u32, gate: int) {

    lapic_timer: Apic_Lvt_Timer;

    set(*lapic_timer, .timer_mode, APIC_TIMER_MODE_PERIODIC);
    set(*lapic_timer, .gate_index, gate);
    set(*lapic_timer, .mask,       0);

    // Todo: we don't currently measure APIC timer frequency, so we can't use a realtime value.
    write_apic_register(.TIC__TIMER_INITIAL, period_in_ticks);
    write_apic_register(.LVT__TIMER, cast(u32)lapic_timer);
}

configure_tsc_deadline_interrupt :: (gate: int) {
    // Mutually exclusive with using the APIC timer interrupt above.

    lapic_timer: Apic_Lvt_Timer;

    set(*lapic_timer, .timer_mode, APIC_TIMER_MODE_TSC_DEADLINE);
    set(*lapic_timer, .gate_index, gate);
    set(*lapic_timer, .mask,       0);

    write_msr(.TSC_DEADLINE, rdtsc() - 1); // Ensure it doesn't fire yet.

    write_apic_register(.LVT__TIMER, cast(u32)lapic_timer);
}

schedule_tsc_deadline_interrupt :: (delay_ms: u64) #no_context {
    delay := (global.tsc_frequency * delay_ms / 1_000);
    write_msr(.TSC_DEADLINE, rdtsc() + delay);
}



initialize_tsc :: () {

    // Check for TSC hardware support.

    edx, ecx: u64;
    #asm {
        edx === d;
        ecx === c;

        mov eax: gpr === a, 0x80000007;
        cpuid eax, ebx:, ecx, edx;
    }

    if edx & 0x200 {
        log("Invariant/Constant TSC Supported.");
    }


    #asm {
        mov eax, 1;
        cpuid eax, ebx, ecx, edx;
    }

    if ecx & (1 << 24) {
        log("TSC_DEADLINE Supported.");
        // TSC Deadline seems to be broken on QEMU on the laptop. Todo.
        // global.tsc_deadline_support = true;
    }

    global.tsc_frequency = calibrate_tsc();
}

calibrate_tsc :: () -> hz: u64 {
    verbose := false;

    // Try to read TSC frequency from CPUID. Modern CPUs support it, but even fairly recent ones don't, in which case we fall back to manual timing using HPET.
    eax, ebx, ecx, edx: u64;

    #asm {
        eax === a;
        ebx === b;
        ecx === c;
        edx === d;

        mov eax, 0x15;
        cpuid eax, ebx, ecx, edx;
    }

    if eax != 0 {
        frequency := ecx * (ebx / eax);
        if verbose log("TSC Frequency is % (CPUID eax=0x15)", frequency);
        return frequency;
    }



    // If the TSC frequency is not provided by CPUID, it can in practice be derived from the processor base frequency.
    #asm {
        mov eax, 0x16;
        cpuid eax, ebx, ecx, edx;
    }

    if eax != 0 {
        // It looks like this value is not too accurate. Manual calibration might be better.
        frequency := eax * 1_000_000;
        if verbose log("TSC Frequency is % (CPUID eax=0x16)", frequency);
        return frequency;
    }



    if verbose log("Calibrating TSC...");
    hpet := global.high_precision_timer;

    calibration_time_fs: u64 = 50_000_000_000_000; // 50ms expressed as femtoseconds

    ticks_per_calibration_run := cast(u32, calibration_time_fs / hpet.tick_period_femtoseconds);

    // Run until we get three consecutive results within a certain error
    max_error := 500_000; // Todo: this value might need to be dynamically estimated, since any specific value will not be reasonable for all possible TSC frequencies.
    delta: [3] int;

    // HPET is off-chip and therefore high latency (1-2us), but it doesn't look like there's a better alternative.
    // Good PDF about OS timekeeping: www.vmware.com/docs/vmware_timekeeping "Timekeeping in VMware Virtual Machines".

    counter_register := cast(*u32, hpet.base_address + cast(u64) Hpet_Register.COUNTER);

    for 1..100 {
        flags := disable_interrupts();

        counter_start := counter_register.*;
        tsc0 := rdtsc();
        tsc1: u64;

        // Todo: it might be best to write the timing loop in assembly, to get the most accurate measurement.
        // Should also write some code to measure the accuracy we're getting. But then again, maybe none of this will be needed on newer microarchitectures, which are the only ones we care about.
        while true {
            counter_now := counter_register.*;

            // rdtsc() is a macro, will not generate a procedure call.
            // But we may want to get rid of the SHL and OR.
            tsc1 = rdtsc();

            if counter_now - counter_start > ticks_per_calibration_run {
                break;
            }
        }

        restore_interrupts(flags);

        delta[2] = delta[1];
        delta[1] = delta[0];
        delta[0] = cast(int, tsc1 - tsc0);

        if verbose log("Run % delta %", it, delta[0]);

        if it < 2 continue;

        abs :: (a: int) -> int {
            if a < 0 return -a;
            return a;
        }

        first_valid  := abs(delta[0] - delta[1]) < max_error;
        second_valid := abs(delta[0] - delta[2]) < max_error;

        if first_valid && second_valid {
            average_delta := (delta[0] + delta[1] + delta[2]) / 3;
            frequency := cast(u64) average_delta * 20; // Convert ticks per 50ms timing run to ticks per second

            if verbose log("Calibrating TSC took % 50ms calibration runs, frequency is %", it, frequency);
            return frequency;
        }
    }

    log_error("Failed to calibrate the Timestamp Counter in good time."); // In the future this routine should never fail, but while the calibration algorithm is not final we'll print this message.
    bluescreen();
    return 0;
}

calibrate_tsc_using_interrupt :: () {
    count := preempt_disable();

    for 1..10 {
        hpet_configure_timer(
            timer_index = 1,
            frequency = 1,
            periodic = false,
        );

        tsc0 := rdtsc();

        while true {
            #asm { hlt; }
            if global.high_precision_timer.timers[1].counter > 0 {
                break;
            }
        }

        tsc1 := rdtsc();

        frequency := tsc1 - tsc0;

        log("Frequency according to 1 second interrupt calibration: %\n", frequency);
    }

    preempt_restore(count);
}

debug_measure_tsc_drift :: () {
    push_print_style().default_format_int.base = 10;

    #asm { cli; }

    tsc_start := rdtsc();
    tsc_frequency := cast(float) global.tsc_frequency;

    time := hpet_get_monotonic_time();

    for 1..1_000_000 {
        time += seconds_to_apollo(1);

        sleep_until(time);
        tsc_now := rdtsc();

        seconds_according_to_tsc := cast(float, tsc_now - tsc_start) / tsc_frequency;

        print("[%] TSC: % | Error: %\n", it, seconds_according_to_tsc, cast(float) it - seconds_according_to_tsc);
    }
}

debug_run_tsc_timer :: () {
    push_print_style().default_format_int.base = 10;

    #asm { cli; }

    tsc_start := rdtsc();
    tsc_frequency := cast(float) global.tsc_frequency;

    seconds: int;

    while true {
        tsc_now := rdtsc();

        seconds_according_to_tsc := cast(float, tsc_now - tsc_start) / tsc_frequency;

        print("%\n", seconds_according_to_tsc);

        for 1..1_000_000 #asm {pause;}
    }
}
