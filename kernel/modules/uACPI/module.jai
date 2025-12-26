//
// This file was auto-generated using the following command:
//
// jai generate_bindings.jai
//



UACPI_PRIu64 :: "llu";
UACPI_PRIx64 :: "llx";
UACPI_PRIX64 :: "llX";

UACPI_THREAD_ID_NONE :: cast,trunc(uacpi_thread_id) -1;

UACPI_DEFAULT_LOOP_TIMEOUT_SECONDS :: 30;

UACPI_DEFAULT_MAX_CALL_STACK_DEPTH :: 256;

UACPI_PLAIN_LOG_BUFFER_SIZE :: 128;

UACPI_STATIC_TABLE_ARRAY_LEN :: 16;

UACPI_INTERRUPT_NOT_HANDLED :: 0;
UACPI_INTERRUPT_HANDLED :: 1;

UACPI_MAX_DEPTH_ANY :: 0xFFFFFFFF;

UACPI_NS_NODE_INFO_HAS_ADR :: 1 << 0;
UACPI_NS_NODE_INFO_HAS_HID :: 1 << 1;
UACPI_NS_NODE_INFO_HAS_UID :: 1 << 2;
UACPI_NS_NODE_INFO_HAS_CID :: 1 << 3;
UACPI_NS_NODE_INFO_HAS_CLS :: 1 << 4;
UACPI_NS_NODE_INFO_HAS_SXD :: 1 << 5;
UACPI_NS_NODE_INFO_HAS_SXW :: 1 << 6;

UACPI_MAJOR :: 3;
UACPI_MINOR :: 2;
UACPI_PATCH :: 0;

UACPI_FLAG_BAD_CSUM_FATAL :: 1 << 0;

UACPI_FLAG_BAD_TBL_SIGNATURE_FATAL :: 1 << 1;

UACPI_FLAG_BAD_XSDT :: 1 << 2;

UACPI_FLAG_NO_ACPI_MODE :: 1 << 3;

UACPI_FLAG_NO_OSI :: 1 << 4;

UACPI_FLAG_PROACTIVE_TBL_CSUM :: 1 << 5;

UACPI_TRIGGERING_EDGE :: 1;
UACPI_TRIGGERING_LEVEL :: 0;

UACPI_POLARITY_ACTIVE_HIGH :: 0;
UACPI_POLARITY_ACTIVE_LOW :: 1;
UACPI_POLARITY_ACTIVE_BOTH :: 2;

UACPI_EXCLUSIVE :: 0;
UACPI_SHARED :: 1;

UACPI_WAKE_CAPABLE :: 1;
UACPI_NOT_WAKE_CAPABLE :: 0;

UACPI_TRANSFER_TYPE_8_BIT :: 0b00;
UACPI_TRANSFER_TYPE_8_AND_16_BIT :: 0b01;
UACPI_TRANSFER_TYPE_16_BIT :: 0b10;

UACPI_BUS_MASTER :: 0b1;

UACPI_DMA_COMPATIBILITY :: 0b00;
UACPI_DMA_TYPE_A :: 0b01;
UACPI_DMA_TYPE_B :: 0b10;
UACPI_DMA_TYPE_F :: 0b11;

UACPI_TRANSFER_WIDTH_8 :: 0x00;
UACPI_TRANSFER_WIDTH_16 :: 0x01;
UACPI_TRANSFER_WIDTH_32 :: 0x02;
UACPI_TRANSFER_WIDTH_64 :: 0x03;
UACPI_TRANSFER_WIDTH_128 :: 0x04;
UACPI_TRANSFER_WIDTH_256 :: 0x05;

UACPI_DECODE_16 :: 0b1;
UACPI_DECODE_10 :: 0b0;

UACPI_NON_WRITABLE :: 0;
UACPI_WRITABLE :: 1;

UACPI_NON_CACHEABLE :: 0;
UACPI_CACHEABLE :: 1;
UACPI_CACHEABLE_WRITE_COMBINING :: 2;
UACPI_PREFETCHABLE :: 3;

UACPI_RANGE_TYPE_MEMORY :: 0;
UACPI_RANGE_TYPE_RESERVED :: 1;
UACPI_RANGE_TYPE_ACPI :: 2;
UACPI_RANGE_TYPE_NVS :: 3;

UACPI_RANGE_MEMORY :: 0;
UACPI_RANGE_IO :: 1;
UACPI_RANGE_BUS :: 2;

UACPI_IO_MEM_TRANSLATION :: 1;
UACPI_IO_MEM_STATIC :: 0;

UACPI_TRANSLATION_DENSE :: 0;
UACPI_TRANSLATION_SPARSE :: 1;

UACPI_PRODUCER :: 0;
UACPI_CONSUMER :: 1;

UACPI_POSITIVE_DECODE :: 0;
UACPI_SUBTRACTIVE_DECODE :: 1;

UACPI_ADDRESS_NOT_FIXED :: 0;
UACPI_ADDRESS_FIXED :: 1;

UACPI_GOOD :: 0;
UACPI_ACCEPTABLE :: 1;
UACPI_SUB_OPTIMAL :: 2;

UACPI_GPIO_CONNECTION_INTERRUPT :: 0x00;
UACPI_GPIO_CONNECTION_IO :: 0x01;

UACPI_IO_RESTRICTION_NONE :: 0x0;
UACPI_IO_RESTRICTION_INPUT :: 0x1;
UACPI_IO_RESTRICTION_OUTPUT :: 0x2;
UACPI_IO_RESTRICTION_NONE_PRESERVE :: 0x3;

UACPI_PIN_CONFIG_DEFAULT :: 0x00;
UACPI_PIN_CONFIG_PULL_UP :: 0x01;
UACPI_PIN_CONFIG_PULL_DOWN :: 0x02;
UACPI_PIN_CONFIG_NO_PULL :: 0x03;

UACPI_MODE_CONTROLLER_INITIATED :: 0x0;
UACPI_MODE_DEVICE_INITIATED :: 0x1;

UACPI_I2C_7BIT :: 0x0;
UACPI_I2C_10BIT :: 0x1;

UACPI_SPI_4_WIRES :: 0;
UACPI_SPI_3_WIRES :: 1;

UACPI_SPI_ACTIVE_LOW :: 0;
UACPI_SPI_ACTIVE_HIGH :: 1;

UACPI_SPI_PHASE_FIRST :: 0;
UACPI_SPI_PHASE_SECOND :: 1;

UACPI_SPI_START_LOW :: 0;
UACPI_SPI_START_HIGH :: 1;

UACPI_UART_STOP_BITS_NONE :: 0b00;
UACPI_UART_STOP_BITS_1 :: 0b01;
UACPI_UART_STOP_BITS_1_5 :: 0b10;
UACPI_UART_STOP_BITS_2 :: 0b11;

UACPI_UART_DATA_5BITS :: 0b000;
UACPI_UART_DATA_6BITS :: 0b001;
UACPI_UART_DATA_7BITS :: 0b010;
UACPI_UART_DATA_8BITS :: 0b011;
UACPI_UART_DATA_9BITS :: 0b100;

UACPI_UART_LITTLE_ENDIAN :: 0;
UACPI_UART_BIG_ENDIAN :: 1;

UACPI_UART_PARITY_NONE :: 0x00;
UACPI_UART_PARITY_EVEN :: 0x01;
UACPI_UART_PARITY_ODD :: 0x02;
UACPI_UART_PARITY_MARK :: 0x03;
UACPI_UART_PARITY_SPACE :: 0x04;

UACPI_UART_DATA_CARRIER_DETECT :: 1 << 2;
UACPI_UART_RING_INDICATOR :: 1 << 3;
UACPI_UART_DATA_SET_READY :: 1 << 4;
UACPI_UART_DATA_TERMINAL_READY :: 1 << 5;
UACPI_UART_CLEAR_TO_SEND :: 1 << 6;
UACPI_UART_REQUEST_TO_SEND :: 1 << 7;

UACPI_UART_FLOW_CONTROL_NONE :: 0b00;
UACPI_UART_FLOW_CONTROL_HW :: 0b01;
UACPI_UART_FLOW_CONTROL_XON_XOFF :: 0b10;

UACPI_CSI2_PHY_C :: 0b00;
UACPI_CSI2_PHY_D :: 0b01;

UACPI_PIN_CONFIG_BIAS_PULL_UP :: 0x01;
UACPI_PIN_CONFIG_BIAS_PULL_DOWN :: 0x02;
UACPI_PIN_CONFIG_BIAS_DEFAULT :: 0x03;
UACPI_PIN_CONFIG_BIAS_DISABLE :: 0x04;
UACPI_PIN_CONFIG_BIAS_HIGH_IMPEDANCE :: 0x05;
UACPI_PIN_CONFIG_BIAS_BUS_HOLD :: 0x06;
UACPI_PIN_CONFIG_DRIVE_OPEN_DRAIN :: 0x07;
UACPI_PIN_CONFIG_DRIVE_OPEN_SOURCE :: 0x08;
UACPI_PIN_CONFIG_DRIVE_PUSH_PULL :: 0x09;
UACPI_PIN_CONFIG_DRIVE_STRENGTH :: 0x0A;
UACPI_PIN_CONFIG_SLEW_RATE :: 0x0B;
UACPI_PIN_CONFIG_INPUT_DEBOUNCE :: 0x0C;
UACPI_PIN_CONFIG_INPUT_SCHMITT_TRIGGER :: 0x0D;

UACPI_SCALE_HZ :: 0b00;
UACPI_SCALE_KHZ :: 0b01;
UACPI_SCALE_MHZ :: 0b10;

UACPI_FREQUENCY_FIXED :: 0x0;
UACPI_FREQUENCY_VARIABLE :: 0x1;

ACPI_RSDP_SIGNATURE :: "RSD PTR ";
ACPI_RSDT_SIGNATURE :: "RSDT";
ACPI_XSDT_SIGNATURE :: "XSDT";
ACPI_MADT_SIGNATURE :: "APIC";
ACPI_FADT_SIGNATURE :: "FACP";
ACPI_FACS_SIGNATURE :: "FACS";
ACPI_MCFG_SIGNATURE :: "MCFG";
ACPI_HPET_SIGNATURE :: "HPET";
ACPI_SRAT_SIGNATURE :: "SRAT";
ACPI_SLIT_SIGNATURE :: "SLIT";
ACPI_DSDT_SIGNATURE :: "DSDT";
ACPI_SSDT_SIGNATURE :: "SSDT";
ACPI_PSDT_SIGNATURE :: "PSDT";
ACPI_ECDT_SIGNATURE :: "ECDT";
ACPI_RHCT_SIGNATURE :: "RHCT";

ACPI_AS_ID_SYS_MEM :: 0x00;
ACPI_AS_ID_SYS_IO :: 0x01;
ACPI_AS_ID_PCI_CFG_SPACE :: 0x02;
ACPI_AS_ID_EC :: 0x03;
ACPI_AS_ID_SMBUS :: 0x04;
ACPI_AS_ID_SYS_CMOS :: 0x05;
ACPI_AS_ID_PCI_BAR_TGT :: 0x06;
ACPI_AS_ID_IPMI :: 0x07;
ACPI_AS_ID_GP_IO :: 0x08;
ACPI_AS_ID_GENERIC_SBUS :: 0x09;
ACPI_AS_ID_PCC :: 0x0A;
ACPI_AS_ID_FFH :: 0x7F;
ACPI_AS_ID_OEM_BASE :: 0xC0;
ACPI_AS_ID_OEM_END :: 0xFF;

ACPI_ACCESS_UD :: 0;
ACPI_ACCESS_BYTE :: 1;
ACPI_ACCESS_WORD :: 2;
ACPI_ACCESS_DWORD :: 3;
ACPI_ACCESS_QWORD :: 4;

ACPI_PCAT_COMPAT :: 1 << 0;

ACPI_PIC_ENABLED :: 1 << 0;
ACPI_PIC_ONLINE_CAPABLE :: 1 << 1;

ACPI_MADT_POLARITY_MASK :: 0b11;
ACPI_MADT_POLARITY_CONFORMING :: 0b00;
ACPI_MADT_POLARITY_ACTIVE_HIGH :: 0b01;
ACPI_MADT_POLARITY_ACTIVE_LOW :: 0b11;

ACPI_MADT_TRIGGERING_MASK :: 0b1100;
ACPI_MADT_TRIGGERING_CONFORMING :: 0b0000;
ACPI_MADT_TRIGGERING_EDGE :: 0b0100;
ACPI_MADT_TRIGGERING_LEVEL :: 0b1100;

ACPI_CPEI_PROCESSOR_OVERRIDE :: 1 << 0;

ACPI_GICC_ENABLED :: 1 << 0;
ACPI_GICC_PERF_INTERRUPT_MODE :: 1 << 1;
ACPI_GICC_VGIC_MAINTENANCE_INTERRUPT_MODE :: 1 << 2;
ACPI_GICC_ONLINE_CAPABLE :: 1 << 3;

ACPI_GICC_TRIGGERING_EDGE :: 1;
ACPI_GICC_TRIGGERING_LEVEL :: 0;

ACPI_SPI_SELECT :: 1 << 0;

ACPI_CORE_PIC_ENABLED :: 1 << 0;

ACPI_SRAT_PROCESSOR_ENABLED :: 1 << 0;

ACPI_SRAT_MEMORY_ENABLED :: 1 << 0;
ACPI_SRAT_MEMORY_HOTPLUGGABLE :: 1 << 1;
ACPI_SRAT_MEMORY_NON_VOLATILE :: 1 << 2;

ACPI_SRAT_GICC_ENABLED :: 1 << 0;

ACPI_GENERIC_AFFINITY_ENABLED :: 1 << 0;
ACPI_GENERIC_AFFINITY_ARCH_TRANSACTIONS :: 1 << 1;

ACPI_SRAT_RINTC_AFFINITY_ENABLED :: 1 << 0;

ACPI_GTDT_TRIGGERING :: 1 << 0;
ACPI_GTDT_TRIGGERING_EDGE :: 1;
ACPI_GTDT_TRIGGERING_LEVEL :: 0;

ACPI_GTDT_POLARITY :: 1 << 1;
ACPI_GTDT_POLARITY_ACTIVE_LOW :: 1;
ACPI_GTDT_POLARITY_ACTIVE_HIGH :: 0;

ACPI_GTDT_ALWAYS_ON_CAPABLE :: 1 << 2;

ACPI_GTDT_TIMER_ENTRY_SECURE :: 1 << 0;
ACPI_GTDT_TIMER_ENTRY_ALWAYS_ON_CAPABLE :: 1 << 1;

ACPI_GTDT_WATCHDOG_SECURE :: 1 << 2;

ACPI_IA_PC_LEGACY_DEVS :: 1 << 0;
ACPI_IA_PC_8042 :: 1 << 1;
ACPI_IA_PC_NO_VGA :: 1 << 2;
ACPI_IA_PC_NO_MSI :: 1 << 3;
ACPI_IA_PC_NO_PCIE_ASPM :: 1 << 4;
ACPI_IA_PC_NO_CMOS_RTC :: 1 << 5;

ACPI_WBINVD :: 1 << 0;
ACPI_WBINVD_FLUSH :: 1 << 1;
ACPI_PROC_C1 :: 1 << 2;
ACPI_P_LVL2_UP :: 1 << 3;
ACPI_PWR_BUTTON :: 1 << 4;
ACPI_SLP_BUTTON :: 1 << 5;
ACPI_FIX_RTC :: 1 << 6;
ACPI_RTC_S4 :: 1 << 7;
ACPI_TMR_VAL_EXT :: 1 << 8;
ACPI_DCK_CAP :: 1 << 9;
ACPI_RESET_REG_SUP :: 1 << 10;
ACPI_SEALED_CASE :: 1 << 11;
ACPI_HEADLESS :: 1 << 12;
ACPI_CPU_SW_SLP :: 1 << 13;
ACPI_PCI_EXP_WAK :: 1 << 14;
ACPI_USE_PLATFORM_CLOCK :: 1 << 15;
ACPI_S4_RTC_STS_VALID :: 1 << 16;
ACPI_REMOTE_POWER_ON_CAPABLE :: 1 << 17;
ACPI_FORCE_APIC_CLUSTER_MODEL :: 1 << 18;
ACPI_FORCE_APIC_PHYS_DEST_MODE :: 1 << 19;
ACPI_HW_REDUCED_ACPI :: 1 << 20;
ACPI_LOW_POWER_S0_IDLE_CAPABLE :: 1 << 21;

ACPI_ARM_PSCI_COMPLIANT :: 1 << 0;
ACPI_ARM_PSCI_USE_HVC :: 1 << 1;

ACPI_S4BIOS_F :: 1 << 0;
ACPI_64BIT_WAKE_SUPPORTED_F :: 1 << 1;

ACPI_64BIT_WAKE_F :: 1 << 0;

ACPI_HPET_PCI_VENDOR_ID_SHIFT :: 16;
ACPI_HPET_LEGACY_REPLACEMENT_IRQ_ROUTING_CAPABLE :: 1 << 15;
ACPI_HPET_COUNT_SIZE_CAP :: 1 << 13;
ACPI_HPET_NUMBER_OF_COMPARATORS_SHIFT :: 8;
ACPI_HPET_NUMBER_OF_COMPARATORS_MASK :: 0b11111;
ACPI_HPET_HARDWARE_REV_ID_MASK :: 0b11111111;

ACPI_HPET_PAGE_PROTECTION_MASK :: 0b11;
ACPI_HPET_PAGE_NO_PROTECTION :: 0;
ACPI_HPET_PAGE_4K_PROTECTED :: 1;
ACPI_HPET_PAGE_64K_PROTECTED :: 2;

ACPI_PM1_STS_TMR_STS_IDX :: 0;
ACPI_PM1_STS_BM_STS_IDX :: 4;
ACPI_PM1_STS_GBL_STS_IDX :: 5;
ACPI_PM1_STS_PWRBTN_STS_IDX :: 8;
ACPI_PM1_STS_SLPBTN_STS_IDX :: 9;
ACPI_PM1_STS_RTC_STS_IDX :: 10;
ACPI_PM1_STS_IGN0_IDX :: 11;
ACPI_PM1_STS_PCIEXP_WAKE_STS_IDX :: 14;
ACPI_PM1_STS_WAKE_STS_IDX :: 15;

ACPI_PM1_STS_TMR_STS_MASK :: 1 << ACPI_PM1_STS_TMR_STS_IDX;
ACPI_PM1_STS_BM_STS_MASK :: 1 << ACPI_PM1_STS_BM_STS_IDX;
ACPI_PM1_STS_GBL_STS_MASK :: 1 << ACPI_PM1_STS_GBL_STS_IDX;
ACPI_PM1_STS_PWRBTN_STS_MASK :: 1 << ACPI_PM1_STS_PWRBTN_STS_IDX;
ACPI_PM1_STS_SLPBTN_STS_MASK :: 1 << ACPI_PM1_STS_SLPBTN_STS_IDX;
ACPI_PM1_STS_RTC_STS_MASK :: 1 << ACPI_PM1_STS_RTC_STS_IDX;
ACPI_PM1_STS_IGN0_MASK :: 1 << ACPI_PM1_STS_IGN0_IDX;
ACPI_PM1_STS_PCIEXP_WAKE_STS_MASK :: 1 << ACPI_PM1_STS_PCIEXP_WAKE_STS_IDX;
ACPI_PM1_STS_WAKE_STS_MASK :: 1 << ACPI_PM1_STS_WAKE_STS_IDX;

ACPI_PM1_STS_CLEAR :: 1;

ACPI_PM1_EN_TMR_EN_IDX :: 0;
ACPI_PM1_EN_GBL_EN_IDX :: 5;
ACPI_PM1_EN_PWRBTN_EN_IDX :: 8;
ACPI_PM1_EN_SLPBTN_EN_IDX :: 9;
ACPI_PM1_EN_RTC_EN_IDX :: 10;
ACPI_PM1_EN_PCIEXP_WAKE_DIS_IDX :: 14;

ACPI_PM1_EN_TMR_EN_MASK :: 1 << ACPI_PM1_EN_TMR_EN_IDX;
ACPI_PM1_EN_GBL_EN_MASK :: 1 << ACPI_PM1_EN_GBL_EN_IDX;
ACPI_PM1_EN_PWRBTN_EN_MASK :: 1 << ACPI_PM1_EN_PWRBTN_EN_IDX;
ACPI_PM1_EN_SLPBTN_EN_MASK :: 1 << ACPI_PM1_EN_SLPBTN_EN_IDX;
ACPI_PM1_EN_RTC_EN_MASK :: 1 << ACPI_PM1_EN_RTC_EN_IDX;
ACPI_PM1_EN_PCIEXP_WAKE_DIS_MASK :: 1 << ACPI_PM1_EN_PCIEXP_WAKE_DIS_IDX;

ACPI_PM1_CNT_SCI_EN_IDX :: 0;
ACPI_PM1_CNT_BM_RLD_IDX :: 1;
ACPI_PM1_CNT_GBL_RLS_IDX :: 2;
ACPI_PM1_CNT_RSVD0_IDX :: 3;
ACPI_PM1_CNT_RSVD1_IDX :: 4;
ACPI_PM1_CNT_RSVD2_IDX :: 5;
ACPI_PM1_CNT_RSVD3_IDX :: 6;
ACPI_PM1_CNT_RSVD4_IDX :: 7;
ACPI_PM1_CNT_RSVD5_IDX :: 8;
ACPI_PM1_CNT_IGN0_IDX :: 9;
ACPI_PM1_CNT_SLP_TYP_IDX :: 10;
ACPI_PM1_CNT_SLP_EN_IDX :: 13;
ACPI_PM1_CNT_RSVD6_IDX :: 14;
ACPI_PM1_CNT_RSVD7_IDX :: 15;

ACPI_SLP_TYP_MAX :: 0x7;

ACPI_PM1_CNT_SCI_EN_MASK :: 1 << ACPI_PM1_CNT_SCI_EN_IDX;
ACPI_PM1_CNT_BM_RLD_MASK :: 1 << ACPI_PM1_CNT_BM_RLD_IDX;
ACPI_PM1_CNT_GBL_RLS_MASK :: 1 << ACPI_PM1_CNT_GBL_RLS_IDX;
ACPI_PM1_CNT_SLP_TYP_MASK :: ACPI_SLP_TYP_MAX << ACPI_PM1_CNT_SLP_TYP_IDX;
ACPI_PM1_CNT_SLP_EN_MASK :: 1 << ACPI_PM1_CNT_SLP_EN_IDX;

ACPI_PM2_CNT_ARB_DIS_IDX :: 0;
ACPI_PM2_CNT_ARB_DIS_MASK :: 1 << ACPI_PM2_CNT_ARB_DIS_IDX;

ACPI_PM2_CNT_PRESERVE_MASK :: ~(cast(uacpi_u64) ACPI_PM2_CNT_ARB_DIS_MASK);

ACPI_SLP_CNT_RSVD0_IDX :: 0;
ACPI_SLP_CNT_IGN0_IDX :: 1;
ACPI_SLP_CNT_SLP_TYP_IDX :: 2;
ACPI_SLP_CNT_SLP_EN_IDX :: 5;
ACPI_SLP_CNT_RSVD1_IDX :: 6;
ACPI_SLP_CNT_RSVD2_IDX :: 7;

ACPI_SLP_CNT_SLP_TYP_MASK :: ACPI_SLP_TYP_MAX << ACPI_SLP_CNT_SLP_TYP_IDX;
ACPI_SLP_CNT_SLP_EN_MASK :: 1 << ACPI_SLP_CNT_SLP_EN_IDX;

ACPI_SLP_STS_WAK_STS_IDX :: 7;

ACPI_SLP_STS_WAK_STS_MASK :: 1 << ACPI_SLP_STS_WAK_STS_IDX;

ACPI_SLP_STS_PRESERVE_MASK :: ~(cast(uacpi_u64) ACPI_SLP_STS_WAK_STS_MASK);

ACPI_SLP_STS_CLEAR :: 1;

ACPI_STA_RESULT_DEVICE_PRESENT :: 1 << 0;
ACPI_STA_RESULT_DEVICE_ENABLED :: 1 << 1;
ACPI_STA_RESULT_DEVICE_SHOWN_IN_UI :: 1 << 2;
ACPI_STA_RESULT_DEVICE_FUNCTIONING :: 1 << 3;
ACPI_STA_RESULT_DEVICE_BATTERY_PRESENT :: 1 << 4;

ACPI_REG_DISCONNECT :: 0;
ACPI_REG_CONNECT :: 1;

ACPI_SPCR_INTERRUPT_TYPE_8259 :: 0x1;
ACPI_SPCR_INTERRUPT_TYPE_IOAPIC :: 0x2;
ACPI_SPCR_INTERRUPT_TYPE_IOSAPIC :: 0x4;
ACPI_SPCR_INTERRUPT_TYPE_GIC :: 0x8;
ACPI_SPCR_INTERRUPT_TYPE_PLIC_APLIC :: 0x10;

ACPI_SPCR_PCI_FLAGS_DO_NOT_DISABLE :: 0x1;

ACPI_TIMER_CANNOT_WAKE_CPU :: 1 << 0;

ACPI_LARGE_ITEM :: 1 << 7;

ACPI_SMALL_ITEM_NAME_IDX :: 3;
ACPI_SMALL_ITEM_NAME_MASK :: 0xF;
ACPI_SMALL_ITEM_LENGTH_MASK :: 0x7;

ACPI_LARGE_ITEM_NAME_MASK :: 0x7F;

ACPI_RESOURCE_IRQ :: 0x04;
ACPI_RESOURCE_DMA :: 0x05;
ACPI_RESOURCE_START_DEPENDENT :: 0x06;
ACPI_RESOURCE_END_DEPENDENT :: 0x07;
ACPI_RESOURCE_IO :: 0x08;
ACPI_RESOURCE_FIXED_IO :: 0x09;
ACPI_RESOURCE_FIXED_DMA :: 0x0A;
ACPI_RESOURCE_VENDOR_TYPE0 :: 0x0E;
ACPI_RESOURCE_END_TAG :: 0x0F;

ACPI_RESOURCE_MEMORY24 :: 0x01;
ACPI_RESOURCE_GENERIC_REGISTER :: 0x02;
ACPI_RESOURCE_VENDOR_TYPE1 :: 0x04;
ACPI_RESOURCE_MEMORY32 :: 0x05;
ACPI_RESOURCE_FIXED_MEMORY32 :: 0x06;
ACPI_RESOURCE_ADDRESS32 :: 0x07;
ACPI_RESOURCE_ADDRESS16 :: 0x08;
ACPI_RESOURCE_EXTENDED_IRQ :: 0x09;
ACPI_RESOURCE_ADDRESS64 :: 0x0A;
ACPI_RESOURCE_ADDRESS64_EXTENDED :: 0x0B;
ACPI_RESOURCE_GPIO_CONNECTION :: 0x0C;
ACPI_RESOURCE_PIN_FUNCTION :: 0x0D;
ACPI_RESOURCE_SERIAL_CONNECTION :: 0x0E;
ACPI_RESOURCE_PIN_CONFIGURATION :: 0x0F;
ACPI_RESOURCE_PIN_GROUP :: 0x10;
ACPI_RESOURCE_PIN_GROUP_FUNCTION :: 0x11;
ACPI_RESOURCE_PIN_GROUP_CONFIGURATION :: 0x12;
ACPI_RESOURCE_CLOCK_INPUT :: 0x13;

ACPI_SERIAL_TYPE_I2C :: 1;
ACPI_SERIAL_TYPE_SPI :: 2;
ACPI_SERIAL_TYPE_UART :: 3;
ACPI_SERIAL_TYPE_CSI2 :: 4;
ACPI_SERIAL_TYPE_MAX :: ACPI_SERIAL_TYPE_CSI2;

UACPI_GPE_REENABLE :: 1 << 7;

uacpi_u8 :: u8;
uacpi_u16 :: u16;
uacpi_u32 :: u32;
uacpi_u64 :: u64;

uacpi_i8 :: s8;
uacpi_i16 :: s16;
uacpi_i32 :: s32;
uacpi_i64 :: s64;

uacpi_bool :: bool;

uacpi_uintptr :: u64;
uacpi_virt_addr :: uacpi_uintptr;
uacpi_size :: u64;

// uacpi_va_list :: va_list;

uacpi_char :: u8;

uacpi_status :: enum u32 {
    OK                           :: 0;
    MAPPING_FAILED               :: 1;
    OUT_OF_MEMORY                :: 2;
    BAD_CHECKSUM                 :: 3;
    INVALID_SIGNATURE            :: 4;
    INVALID_TABLE_LENGTH         :: 5;
    NOT_FOUND                    :: 6;
    INVALID_ARGUMENT             :: 7;
    UNIMPLEMENTED                :: 8;
    ALREADY_EXISTS               :: 9;
    INTERNAL_ERROR               :: 10;
    TYPE_MISMATCH                :: 11;
    INIT_LEVEL_MISMATCH          :: 12;
    NAMESPACE_NODE_DANGLING      :: 13;
    NO_HANDLER                   :: 14;
    NO_RESOURCE_END_TAG          :: 15;
    COMPILED_OUT                 :: 16;
    HARDWARE_TIMEOUT             :: 17;
    TIMEOUT                      :: 18;
    OVERRIDDEN                   :: 19;
    DENIED                       :: 20;

    AML_UNDEFINED_REFERENCE      :: 251592704;
    AML_INVALID_NAMESTRING       :: 251592705;
    AML_OBJECT_ALREADY_EXISTS    :: 251592706;
    AML_INVALID_OPCODE           :: 251592707;
    AML_INCOMPATIBLE_OBJECT_TYPE :: 251592708;
    AML_BAD_ENCODING             :: 251592709;
    AML_OUT_OF_BOUNDS_INDEX      :: 251592710;
    AML_SYNC_LEVEL_TOO_HIGH      :: 251592711;
    AML_INVALID_RESOURCE         :: 251592712;
    AML_LOOP_TIMEOUT             :: 251592713;
    AML_CALL_STACK_DEPTH_LIMIT   :: 251592714;
}

uacpi_status_to_string :: (unknown0: uacpi_status) -> *uacpi_char #foreign uacpi;

uacpi_cpu_flags :: u64;

uacpi_thread_id :: *void;

uacpi_log_level :: enum u32 {
    DEBUG :: 5;

    TRACE :: 4;

    INFO  :: 3;

    WARN  :: 2;

    ERROR :: 1;
}

uacpi_phys_addr :: uacpi_u64;
uacpi_io_addr :: uacpi_u64;

uacpi_handle :: *void;

uacpi_object_name :: union {
    text: [4] uacpi_char;
    id:   uacpi_u32;
}

uacpi_iteration_decision :: enum u32 {
    CONTINUE  :: 0;
    BREAK     :: 1;

    NEXT_PEER :: 2;
}

uacpi_address_space :: enum u32 {
    SYSTEM_MEMORY       :: 0;
    SYSTEM_IO           :: 1;
    PCI_CONFIG          :: 2;
    EMBEDDED_CONTROLLER :: 3;
    SMBUS               :: 4;
    SYSTEM_CMOS         :: 5;
    PCI_BAR_TARGET      :: 6;
    IPMI                :: 7;
    GENERAL_PURPOSE_IO  :: 8;
    GENERIC_SERIAL_BUS  :: 9;
    PCC                 :: 10;
    PRM                 :: 11;
    FFIXEDHW            :: 127;

    TABLE_DATA          :: 55834;
}

uacpi_address_space_to_string :: (space: uacpi_address_space) -> *uacpi_char #foreign uacpi;

uacpi_init_level :: enum u32 {
    EARLY                 :: 0;

    SUBSYSTEM_INITIALIZED :: 1;

    NAMESPACE_LOADED      :: 2;

    NAMESPACE_INITIALIZED :: 3;
}

uacpi_pci_address :: struct {
    segment:  uacpi_u16;
    bus:      uacpi_u8;
    device:   uacpi_u8;
    function: uacpi_u8;
}

uacpi_data_view :: struct {
    union {
        bytes:       *uacpi_u8;
        const_bytes: *uacpi_u8;

        text:        *uacpi_char;
        const_text:  *uacpi_char;

        data:        *void;
        const_data:  *void;
    }

    length: uacpi_size;
}

uacpi_namespace_node :: struct {}

uacpi_object_type :: enum u32 {
    UNINITIALIZED    :: 0;
    INTEGER          :: 1;
    STRING           :: 2;
    BUFFER           :: 3;
    PACKAGE          :: 4;
    FIELD_UNIT       :: 5;
    DEVICE           :: 6;
    EVENT            :: 7;
    METHOD           :: 8;
    MUTEX            :: 9;
    OPERATION_REGION :: 10;
    POWER_RESOURCE   :: 11;
    PROCESSOR        :: 12;
    THERMAL_ZONE     :: 13;
    BUFFER_FIELD     :: 14;
    DEBUG            :: 16;

    REFERENCE        :: 20;
    BUFFER_INDEX     :: 21;
    MAX_TYPE_VALUE   :: 21;
}

// Type bits for API requiring a bit mask, e.g. uacpi_eval_typed
uacpi_object_type_bits :: enum u32 {
    INTEGER_BIT          :: 2;
    STRING_BIT           :: 4;
    BUFFER_BIT           :: 8;
    PACKAGE_BIT          :: 16;
    FIELD_UNIT_BIT       :: 32;
    DEVICE_BIT           :: 64;
    EVENT_BIT            :: 128;
    METHOD_BIT           :: 256;
    MUTEX_BIT            :: 512;
    OPERATION_REGION_BIT :: 1024;
    POWER_RESOURCE_BIT   :: 2048;
    PROCESSOR_BIT        :: 4096;
    THERMAL_ZONE_BIT     :: 8192;
    BUFFER_FIELD_BIT     :: 16384;
    DEBUG_BIT            :: 65536;
    REFERENCE_BIT        :: 1048576;
    BUFFER_INDEX_BIT     :: 2097152;
    ANY_BIT              :: 4294967295;
}

uacpi_object :: struct {}

uacpi_object_ref :: (obj: *uacpi_object) -> void #foreign uacpi;
uacpi_object_unref :: (obj: *uacpi_object) -> void #foreign uacpi;

uacpi_object_get_type :: (unknown0: *uacpi_object) -> uacpi_object_type #foreign uacpi;
uacpi_object_get_type_bit :: (unknown0: *uacpi_object) -> uacpi_object_type_bits #foreign uacpi;

/*
* Returns UACPI_TRUE if the provided object's type matches this type.
*/
uacpi_object_is :: (unknown0: *uacpi_object, unknown1: uacpi_object_type) -> uacpi_bool #foreign uacpi;

/*
* Returns UACPI_TRUE if the provided object's type is one of the values
* specified in the 'type_mask' of UACPI_OBJECT_*_BIT.
*/
uacpi_object_is_one_of :: (unknown0: *uacpi_object, type_mask: uacpi_object_type_bits) -> uacpi_bool #foreign uacpi;

uacpi_object_type_to_string :: (unknown0: uacpi_object_type) -> *uacpi_char #foreign uacpi;

/*
* Create an uninitialized object. The object can be further overwritten via
* uacpi_object_assign_* to anything.
*/
uacpi_object_create_uninitialized :: () -> *uacpi_object #foreign uacpi;

/*
* Create an integer object with the value provided.
*/
uacpi_object_create_integer :: (unknown0: uacpi_u64) -> *uacpi_object #foreign uacpi;

uacpi_overflow_behavior :: enum u32 {
    ALLOW    :: 0;
    TRUNCATE :: 1;
    DISALLOW :: 2;
}

/*
* Same as uacpi_object_create_integer, but introduces additional ways to
* control what happens if the provided integer is larger than 32-bits, and the
* AML code expects 32-bit integers.
*
* - UACPI_OVERFLOW_ALLOW -> do nothing, same as the vanilla helper
* - UACPI_OVERFLOW_TRUNCATE -> truncate the integer to 32-bits if it happens to
*                              be larger than allowed by the DSDT
* - UACPI_OVERFLOW_DISALLOW -> fail object creation with
*                              UACPI_STATUS_INVALID_ARGUMENT if the provided
*                              value happens to be too large
*/
uacpi_object_create_integer_safe :: (unknown0: uacpi_u64, unknown1: uacpi_overflow_behavior, out_obj: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_object_assign_integer :: (unknown0: *uacpi_object, value: uacpi_u64) -> uacpi_status #foreign uacpi;
uacpi_object_get_integer :: (unknown0: *uacpi_object, out: *uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* Create a string/buffer object. Takes in a constant view of the data.
*
* NOTE: The data is copied to a separately allocated buffer and is not taken
*       ownership of.
*/
uacpi_object_create_string :: (unknown0: uacpi_data_view) -> *uacpi_object #foreign uacpi;
uacpi_object_create_cstring :: (unknown0: *uacpi_char) -> *uacpi_object #foreign uacpi;
uacpi_object_create_buffer :: (unknown0: uacpi_data_view) -> *uacpi_object #foreign uacpi;

/*
* Returns a writable view of the data stored in the string or buffer type
* object.
*/
uacpi_object_get_string_or_buffer :: (unknown0: *uacpi_object, out: *uacpi_data_view) -> uacpi_status #foreign uacpi;

uacpi_object_get_string :: (unknown0: *uacpi_object, out: *uacpi_data_view) -> uacpi_status #foreign uacpi;
uacpi_object_get_buffer :: (unknown0: *uacpi_object, out: *uacpi_data_view) -> uacpi_status #foreign uacpi;

/*
* Returns UACPI_TRUE if the provided string object is actually an AML namepath.
*
* This can only be the case for package elements. If a package element is
* specified as a path to an object in AML, it's not resolved by the interpreter
* right away as it might not have been defined at that point yet, and is
* instead stored as a special string object to be resolved by client code
* when needed.
*
* Example usage:
*     uacpi_namespace_node *target_node = UACPI_NULL;
*
*     uacpi_object *obj = UACPI_NULL;
*     uacpi_eval(scope, path, UACPI_NULL, &obj);
*
*     uacpi_object_array arr;
*     uacpi_object_get_package(obj, &arr);
*
*     if (uacpi_object_is_aml_namepath(arr.objects[0])) {
*         uacpi_object_resolve_as_aml_namepath(
*             arr.objects[0], scope, &target_node
*         );
*     }
*/
uacpi_object_is_aml_namepath :: (unknown0: *uacpi_object) -> uacpi_bool #foreign uacpi;

/*
* Resolve an AML namepath contained in a string object.
*
* This is only applicable to objects that are package elements. See an
* explanation of how this works in the comment above the declaration of
* uacpi_object_is_aml_namepath.
*
* This is a shorthand for:
*     uacpi_data_view view;
*     uacpi_object_get_string(object, &view);
*
*     target_node = uacpi_namespace_node_resolve_from_aml_namepath(
*         scope, view.text
*     );
*/
uacpi_object_resolve_as_aml_namepath :: (unknown0: *uacpi_object, scope: *uacpi_namespace_node, out_node: **uacpi_namespace_node) -> uacpi_status #foreign uacpi;

/*
* Make the provided object a string/buffer.
* Takes in a constant view of the data to be stored in the object.
*
* NOTE: The data is copied to a separately allocated buffer and is not taken
*       ownership of.
*/
uacpi_object_assign_string :: (unknown0: *uacpi_object, in: uacpi_data_view) -> uacpi_status #foreign uacpi;
uacpi_object_assign_buffer :: (unknown0: *uacpi_object, in: uacpi_data_view) -> uacpi_status #foreign uacpi;

uacpi_object_array :: struct {
    objects: **uacpi_object;
    count:   uacpi_size;
}

/*
* Create a package object and store all of the objects in the array inside.
* The array is allowed to be empty.
*
* NOTE: the reference count of each object is incremented before being stored
*       in the object. Client code must remove all of the locally created
*       references at its own discretion.
*/
uacpi_object_create_package :: (in: uacpi_object_array) -> *uacpi_object #foreign uacpi;

/*
* Returns the list of objects stored in a package object.
*
* NOTE: the reference count of the objects stored inside is not incremented,
*       which means destorying/overwriting the object also potentially destroys
*       all of the objects stored inside unless the reference count is
*       incremented by the client via uacpi_object_ref.
*/
uacpi_object_get_package :: (unknown0: *uacpi_object, out: *uacpi_object_array) -> uacpi_status #foreign uacpi;

/*
* Make the provided object a package and store all of the objects in the array
* inside. The array is allowed to be empty.
*
* NOTE: the reference count of each object is incremented before being stored
*       in the object. Client code must remove all of the locally created
*       references at its own discretion.
*/
uacpi_object_assign_package :: (unknown0: *uacpi_object, in: uacpi_object_array) -> uacpi_status #foreign uacpi;

/*
* Create a reference object and make it point to 'child'.
*
* NOTE: child's reference count is incremented by one. Client code must remove
*       all of the locally created references at its own discretion.
*/
uacpi_object_create_reference :: (child: *uacpi_object) -> *uacpi_object #foreign uacpi;

/*
* Make the provided object a reference and make it point to 'child'.
*
* NOTE: child's reference count is incremented by one. Client code must remove
*       all of the locally created references at its own discretion.
*/
uacpi_object_assign_reference :: (unknown0: *uacpi_object, child: *uacpi_object) -> uacpi_status #foreign uacpi;

/*
* Retrieve the object pointed to by a reference object.
*
* NOTE: the reference count of the returned object is incremented by one and
*       must be uacpi_object_unref'ed by the client when no longer needed.
*/
uacpi_object_get_dereferenced :: (unknown0: *uacpi_object, out: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_processor_info :: struct {
    id:            uacpi_u8;
    block_address: uacpi_u32;
    block_length:  uacpi_u8;
}

/*
* Returns the information about the provided processor object.
*/
uacpi_object_get_processor_info :: (unknown0: *uacpi_object, out: *uacpi_processor_info) -> uacpi_status #foreign uacpi;

uacpi_power_resource_info :: struct {
    system_level:   uacpi_u8;
    resource_order: uacpi_u16;
}

/*
* Returns the information about the provided power resource object.
*/
uacpi_object_get_power_resource_info :: (unknown0: *uacpi_object, out: *uacpi_power_resource_info) -> uacpi_status #foreign uacpi;

uacpi_region_op :: enum u32 {
    ATTACH           :: 0;

    DETACH           :: 1;

    READ             :: 2;
    WRITE            :: 3;

    PCC_SEND         :: 4;

    GPIO_READ        :: 5;
    GPIO_WRITE       :: 6;

    IPMI_COMMAND     :: 7;

    FFIXEDHW_COMMAND :: 8;

    PRM_COMMAND      :: 9;

    SERIAL_READ      :: 10;
    SERIAL_WRITE     :: 11;
}

uacpi_generic_region_info :: struct {
    base:   uacpi_u64;
    length: uacpi_u64;
}

uacpi_pcc_region_info :: struct {
    buffer:      uacpi_data_view;
    subspace_id: uacpi_u8;
}

uacpi_gpio_region_info :: struct {
    num_pins: uacpi_u64;
}

uacpi_region_attach_data :: struct {
    handler_context:    *void;
    region_node:        *uacpi_namespace_node;
    union {
        generic_info: uacpi_generic_region_info;
        pcc_info:     uacpi_pcc_region_info;
        gpio_info:    uacpi_gpio_region_info;
    }

    out_region_context: *void;
}

uacpi_region_rw_data :: struct {
    handler_context: *void;
    region_context:  *void;
    union {
        address: uacpi_phys_addr;
        offset:  uacpi_u64;
    }

    value:           uacpi_u64;
    byte_width:      uacpi_u8;
}

uacpi_region_pcc_send_data :: struct {
    handler_context: *void;
    region_context:  *void;
    buffer:          uacpi_data_view;
}

uacpi_region_gpio_rw_data :: struct {
    handler_context: *void;
    region_context:  *void;
    connection:      uacpi_data_view;
    pin_offset:      uacpi_u32;
    num_pins:        uacpi_u32;
    value:           uacpi_u64;
}

uacpi_region_ipmi_rw_data :: struct {
    handler_context: *void;
    region_context:  *void;
    in_out_message:  uacpi_data_view;
    command:         uacpi_u64;
}

uacpi_region_ffixedhw_rw_data :: uacpi_region_ipmi_rw_data;

uacpi_region_prm_rw_data :: struct {
    handler_context: *void;
    region_context:  *void;
    in_out_message:  uacpi_data_view;
}

uacpi_access_attribute :: enum u32 {
    QUICK              :: 2;
    SEND_RECEIVE       :: 4;
    BYTE               :: 6;
    WORD               :: 8;
    BLOCK              :: 10;
    BYTES              :: 11;
    PROCESS_CALL       :: 12;
    BLOCK_PROCESS_CALL :: 13;
    RAW_BYTES          :: 14;
    RAW_PROCESS_BYTES  :: 15;
}

uacpi_region_serial_rw_data :: struct {
    handler_context:  *void;
    region_context:   *void;
    command:          uacpi_u64;
    connection:       uacpi_data_view;
    in_out_buffer:    uacpi_data_view;
    access_attribute: uacpi_access_attribute;

    /*
    * Applicable if access_attribute is one of:
    * - UACPI_ACCESS_ATTRIBUTE_BYTES
    * - UACPI_ACCESS_ATTRIBUTE_RAW_BYTES
    * - UACPI_ACCESS_ATTRIBUTE_RAW_PROCESS_BYTES
    */
    access_length:    uacpi_u8;
}

uacpi_region_detach_data :: struct {
    handler_context: *void;
    region_context:  *void;
    region_node:     *uacpi_namespace_node;
}

uacpi_region_handler :: #type (op: uacpi_region_op, op_data: uacpi_handle) -> uacpi_status #c_call;

uacpi_notify_handler :: #type (_context: uacpi_handle, node: *uacpi_namespace_node, value: uacpi_u64) -> uacpi_status #c_call;

uacpi_firmware_request_type :: enum u32 {
    BREAKPOINT :: 0;
    FATAL      :: 1;
}

uacpi_firmware_request :: struct {
    type: uacpi_u8;

    union {
        breakpoint: struct {
            // The context of the method currently being executed
            ctx: uacpi_handle;
        };

        fatal:      struct {
            type: uacpi_u8;
            code: uacpi_u32;
            arg:  uacpi_u64;
        };
    }
}

uacpi_interrupt_ret :: uacpi_u32;

uacpi_interrupt_handler :: #type (unknown0: uacpi_handle) -> uacpi_interrupt_ret #c_call;

uacpi_namespace_root :: () -> *uacpi_namespace_node #foreign uacpi;

uacpi_predefined_namespace :: enum u32 {
    ROOT :: 0;
    GPE  :: 1;
    PR   :: 2;
    SB   :: 3;
    SI   :: 4;
    TZ   :: 5;
    GL   :: 6;
    OS   :: 7;
    OSI  :: 8;
    REV  :: 9;
    MAX  :: 9;
}

uacpi_namespace_get_predefined :: (unknown0: uacpi_predefined_namespace) -> *uacpi_namespace_node #foreign uacpi;

/*
* Returns UACPI_TRUE if the provided 'node' is an alias.
*/
uacpi_namespace_node_is_alias :: (node: *uacpi_namespace_node) -> uacpi_bool #foreign uacpi;

uacpi_namespace_node_name :: (node: *uacpi_namespace_node) -> uacpi_object_name #foreign uacpi;

/*
* Returns the type of object stored at the namespace node.
*
* NOTE: due to the existance of the CopyObject operator in AML, the
*       return value of this function is subject to TOCTOU bugs.
*/
uacpi_namespace_node_type :: (node: *uacpi_namespace_node, out_type: *uacpi_object_type) -> uacpi_status #foreign uacpi;

/*
* Returns UACPI_TRUE via 'out' if the type of the object stored at the
* namespace node matches the provided value, UACPI_FALSE otherwise.
*
* NOTE: due to the existance of the CopyObject operator in AML, the
*       return value of this function is subject to TOCTOU bugs.
*/
uacpi_namespace_node_is :: (node: *uacpi_namespace_node, type: uacpi_object_type, out: *uacpi_bool) -> uacpi_status #foreign uacpi;

/*
* Returns UACPI_TRUE via 'out' if the type of the object stored at the
* namespace node matches any of the type bits in the provided value,
* UACPI_FALSE otherwise.
*
* NOTE: due to the existance of the CopyObject operator in AML, the
*       return value of this function is subject to TOCTOU bugs.
*/
uacpi_namespace_node_is_one_of :: (node: *uacpi_namespace_node, type_mask: uacpi_object_type_bits, out: *uacpi_bool) -> uacpi_status #foreign uacpi;

uacpi_namespace_node_depth :: (node: *uacpi_namespace_node) -> uacpi_size #foreign uacpi;

uacpi_namespace_node_parent :: (node: *uacpi_namespace_node) -> *uacpi_namespace_node #foreign uacpi;

uacpi_namespace_node_find :: (parent: *uacpi_namespace_node, path: *uacpi_char, out_node: **uacpi_namespace_node) -> uacpi_status #foreign uacpi;

/*
* Same as uacpi_namespace_node_find, except the search recurses upwards when
* the namepath consists of only a single nameseg. Usually, this behavior is
* only desired if resolving a namepath specified in an aml-provided object,
* such as a package element.
*/
uacpi_namespace_node_resolve_from_aml_namepath :: (scope: *uacpi_namespace_node, path: *uacpi_char, out_node: **uacpi_namespace_node) -> uacpi_status #foreign uacpi;

uacpi_iteration_callback :: #type (user: *void, node: *uacpi_namespace_node, node_depth: uacpi_u32) -> uacpi_iteration_decision #c_call;

/*
* Depth-first iterate the namespace starting at the first child of 'parent'.
*/
uacpi_namespace_for_each_child_simple :: (parent: *uacpi_namespace_node, callback: uacpi_iteration_callback, user: *void) -> uacpi_status #foreign uacpi;

/*
* Depth-first iterate the namespace starting at the first child of 'parent'.
*
* 'descending_callback' is invoked the first time a node is visited when
* walking down. 'ascending_callback' is invoked the second time a node is
* visited after we reach the leaf node without children and start walking up.
* Either of the callbacks may be NULL, but not both at the same time.
*
* Only nodes matching 'type_mask' are passed to the callbacks.
*
* 'max_depth' is used to limit the maximum reachable depth from 'parent',
* where 1 is only direct children of 'parent', 2 is children of first-level
* children etc. Use UACPI_MAX_DEPTH_ANY or -1 to specify infinite depth.
*/
uacpi_namespace_for_each_child :: (parent: *uacpi_namespace_node, descending_callback: uacpi_iteration_callback, ascending_callback: uacpi_iteration_callback, type_mask: uacpi_object_type_bits, max_depth: uacpi_u32, user: *void) -> uacpi_status #foreign uacpi;

/*
* Retrieve the next peer namespace node of '*iter', or, if '*iter' is
* UACPI_NULL, retrieve the first child of 'parent' instead. The resulting
* namespace node is stored at '*iter'.
*
* This API can be used to implement an "iterator" version of the
* for_each_child helpers.
*
* Example usage:
*     void recurse(uacpi_namespace_node *parent) {
*        uacpi_namespace_node *iter = UACPI_NULL;
*
*        while (uacpi_namespace_node_next(parent, &iter) == UACPI_STATUS_OK) {
*             // Do something with iter...
*             descending_callback(iter);
*
*             // Recurse down to walk over the children of iter
*             recurse(iter);
*        }
*     }
*
* Prefer the for_each_child family of helpers if possible instead of this API
* as they avoid recursion and/or the need to use dynamic data structures
* entirely.
*/
uacpi_namespace_node_next :: (parent: *uacpi_namespace_node, iter: **uacpi_namespace_node) -> uacpi_status #foreign uacpi;

/*
* Retrieve the next peer namespace node of '*iter', or, if '*iter' is
* UACPI_NULL, retrieve the first child of 'parent' instead. The resulting
* namespace node is stored at '*iter'. Only nodes which type matches one
* of the types set in 'type_mask' are returned.
*
* See comment above 'uacpi_namespace_node_next' for usage examples.
*
* Prefer the for_each_child family of helpers if possible instead of this API
* as they avoid recursion and/or the need to use dynamic data structures
* entirely.
*/
uacpi_namespace_node_next_typed :: (parent: *uacpi_namespace_node, iter: **uacpi_namespace_node, type_mask: uacpi_object_type_bits) -> uacpi_status #foreign uacpi;

uacpi_namespace_node_generate_absolute_path :: (node: *uacpi_namespace_node) -> *uacpi_char #foreign uacpi;

uacpi_free_absolute_path :: (path: *uacpi_char) -> void #foreign uacpi;

/*
* Checks whether the device at 'node' matches any of the PNP ids provided in
* 'list' (terminated by a UACPI_NULL). This is done by first attempting to
* match the value returned from _HID and then the value(s) from _CID.
*
* Note that the presence of the device (_STA) is not verified here.
*/
uacpi_device_matches_pnp_id :: (node: *uacpi_namespace_node, list: **uacpi_char) -> uacpi_bool #foreign uacpi;

/*
* Find all the devices in the namespace starting at 'parent' matching the
* specified 'hids' (terminated by a UACPI_NULL) against any value from _HID or
* _CID. Only devices reported as present via _STA are checked. Any matching
* devices are then passed to the 'cb'.
*/
uacpi_find_devices_at :: (parent: *uacpi_namespace_node, hids: **uacpi_char, cb: uacpi_iteration_callback, user: *void) -> uacpi_status #foreign uacpi;

/*
* Same as uacpi_find_devices_at, except this starts at the root and only
* matches one hid.
*/
uacpi_find_devices :: (hid: *uacpi_char, cb: uacpi_iteration_callback, user: *void) -> uacpi_status #foreign uacpi;

uacpi_interrupt_model :: enum u32 {
    PIC               :: 0;
    IOAPIC            :: 1;
    IOSAPIC           :: 2;
    PLATFORM_SPECIFIC :: 3;
    GIC               :: 4;
    LPIC              :: 5;
    RINTC             :: 6;
}

uacpi_set_interrupt_model :: (unknown0: uacpi_interrupt_model) -> uacpi_status #foreign uacpi;

uacpi_pci_routing_table_entry :: struct {
    address: uacpi_u32;
    index:   uacpi_u32;
    source:  *uacpi_namespace_node;
    pin:     uacpi_u8;
}

uacpi_pci_routing_table :: struct {
    num_entries: uacpi_size;
//     entries:     *uacpi_pci_routing_table_entry;// Incomplete array in C (zero-sized)
}

uacpi_free_pci_routing_table :: (unknown0: *uacpi_pci_routing_table) -> void #foreign uacpi;

uacpi_get_pci_routing_table :: (parent: *uacpi_namespace_node, out_table: **uacpi_pci_routing_table) -> uacpi_status #foreign uacpi;

uacpi_id_string :: struct {
    // size of the string including the null byte
    size:  uacpi_u32;
    value: *uacpi_char;
}

uacpi_free_id_string :: (id: *uacpi_id_string) -> void #foreign uacpi;

/*
* Evaluate a device's _HID method and get its value.
* The returned struture must be freed using uacpi_free_id_string.
*/
uacpi_eval_hid :: (unknown0: *uacpi_namespace_node, out_id: **uacpi_id_string) -> uacpi_status #foreign uacpi;

uacpi_pnp_id_list :: struct {
    // number of 'ids' in the list
    num_ids: uacpi_u32;

    // size of the 'ids' list including the string lengths
    size:    uacpi_u32;

//     // list of PNP ids
    ids:     *uacpi_id_string;// Incomplete array in C (zero-sized)
}

uacpi_free_pnp_id_list :: (list: *uacpi_pnp_id_list) -> void #foreign uacpi;

/*
* Evaluate a device's _CID method and get its value.
* The returned structure must be freed using uacpi_free_pnp_id_list.
*/
uacpi_eval_cid :: (unknown0: *uacpi_namespace_node, out_list: **uacpi_pnp_id_list) -> uacpi_status #foreign uacpi;

/*
* Evaluate a device's _STA method and get its value.
* If this method is not found, the value of 'flags' is set to all ones.
*/
uacpi_eval_sta :: (unknown0: *uacpi_namespace_node, flags: *uacpi_u32) -> uacpi_status #foreign uacpi;

/*
* Evaluate a device's _ADR method and get its value.
*/
uacpi_eval_adr :: (unknown0: *uacpi_namespace_node, out: *uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* Evaluate a device's _CLS method and get its value.
* The format of returned string is BBSSPP where:
*     BB => Base Class (e.g. 01 => Mass Storage)
*     SS => Sub-Class (e.g. 06 => SATA)
*     PP => Programming Interface (e.g. 01 => AHCI)
* The returned struture must be freed using uacpi_free_id_string.
*/
uacpi_eval_cls :: (unknown0: *uacpi_namespace_node, out_id: **uacpi_id_string) -> uacpi_status #foreign uacpi;

/*
* Evaluate a device's _UID method and get its value.
* The returned struture must be freed using uacpi_free_id_string.
*/
uacpi_eval_uid :: (unknown0: *uacpi_namespace_node, out_uid: **uacpi_id_string) -> uacpi_status #foreign uacpi;

uacpi_namespace_node_info :: struct {
    // Size of the entire structure
    size:       uacpi_u32;

    // Object information
    name:       uacpi_object_name;
    type:       uacpi_object_type;
    num_params: uacpi_u8;

    // UACPI_NS_NODE_INFO_HAS_*
    flags:      uacpi_u8;

    /*
    * A mapping of [S1..S4] to the shallowest D state supported by the device
    * in that S state.
    */
    sxd:        [4] uacpi_u8;

    /*
    * A mapping of [S0..S4] to the deepest D state supported by the device
    * in that S state to be able to wake itself.
    */
    sxw:        [5] uacpi_u8;

    adr:        uacpi_u64;
    hid:        uacpi_id_string;
    uid:        uacpi_id_string;
    cls:        uacpi_id_string;
    cid:        uacpi_pnp_id_list;
}

uacpi_free_namespace_node_info :: (unknown0: *uacpi_namespace_node_info) -> void #foreign uacpi;

/*
* Retrieve information about a namespace node. This includes the attached
* object's type, name, number of parameters (if it's a method), the result of
* evaluating _ADR, _UID, _CLS, _HID, _CID, as well as _SxD and _SxW.
*
* The returned structure must be freed with uacpi_free_namespace_node_info.
*/
uacpi_get_namespace_node_info :: (node: *uacpi_namespace_node, out_info: **uacpi_namespace_node_info) -> uacpi_status #foreign uacpi;

uacpi_work_type :: enum u32 {
    GPE_EXECUTION :: 0;

    NOTIFICATION  :: 1;
}

uacpi_work_handler :: #type (unknown0: uacpi_handle) -> void #c_call;

/*
* Set up early access to the table subsystem. What this means is:
* - uacpi_table_find() and similar API becomes usable before the call to
*   uacpi_initialize().
* - No kernel API besides logging and map/unmap will be invoked at this stage,
*   allowing for heap and scheduling to still be fully offline.
* - The provided 'temporary_buffer' will be used as a temporary storage for the
*   internal metadata about the tables (list, reference count, addresses,
*   sizes, etc).
* - The 'temporary_buffer' is replaced with a normal heap buffer allocated via
*   uacpi_kernel_alloc() after the call to uacpi_initialize() and can therefore
*   be reclaimed by the kernel.
*
* The approximate overhead per table is 56 bytes, so a buffer of 4096 bytes
* yields about 73 tables in terms of capacity. uACPI also has an internal
* static buffer for tables, "UACPI_STATIC_TABLE_ARRAY_LEN", which is configured
* as 16 descriptors in length by default.
*
* This function is used to initialize the barebones mode, see
* UACPI_BAREBONES_MODE in config.h for more information.
*/
uacpi_setup_early_table_access :: (temporary_buffer: *void, buffer_size: uacpi_size) -> uacpi_status #foreign uacpi;

/*
* Initializes the uACPI subsystem, iterates & records all relevant RSDT/XSDT
* tables. Enters ACPI mode.
*
* 'flags' is any combination of UACPI_FLAG_* above
*/
uacpi_initialize :: (flags: uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* Parses & executes all of the DSDT/SSDT tables.
* Initializes the event subsystem.
*/
uacpi_namespace_load :: () -> uacpi_status #foreign uacpi;

/*
* Initializes all the necessary objects in the namespaces by calling
* _STA/_INI etc.
*/
uacpi_namespace_initialize :: () -> uacpi_status #foreign uacpi;

// Returns the current subsystem initialization level
uacpi_get_current_init_level :: () -> uacpi_init_level #foreign uacpi;

/*
* Evaluate an object within the namespace and get back its value.
* Either root or path must be valid.
* A value of NULL for 'parent' implies uacpi_namespace_root() relative
* lookups, unless 'path' is already absolute.
*/
uacpi_eval :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_eval_simple :: (parent: *uacpi_namespace_node, path: *uacpi_char, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

/*
* Same as uacpi_eval() but without a return value.
*/
uacpi_execute :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array) -> uacpi_status #foreign uacpi;

uacpi_execute_simple :: (parent: *uacpi_namespace_node, path: *uacpi_char) -> uacpi_status #foreign uacpi;

/*
* Same as uacpi_eval, but the return value type is validated against
* the 'ret_mask'. UACPI_STATUS_TYPE_MISMATCH is returned on error.
*/
uacpi_eval_typed :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array, ret_mask: uacpi_object_type_bits, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_eval_simple_typed :: (parent: *uacpi_namespace_node, path: *uacpi_char, ret_mask: uacpi_object_type_bits, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

/*
* A shorthand for uacpi_eval_typed with UACPI_OBJECT_INTEGER_BIT.
*/
uacpi_eval_integer :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array, out_value: *uacpi_u64) -> uacpi_status #foreign uacpi;

uacpi_eval_simple_integer :: (parent: *uacpi_namespace_node, path: *uacpi_char, out_value: *uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* A shorthand for uacpi_eval_typed with
*     UACPI_OBJECT_BUFFER_BIT | UACPI_OBJECT_STRING_BIT
*
* Use uacpi_object_get_string_or_buffer to retrieve the resulting buffer data.
*/
uacpi_eval_buffer_or_string :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_eval_simple_buffer_or_string :: (parent: *uacpi_namespace_node, path: *uacpi_char, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

/*
* A shorthand for uacpi_eval_typed with UACPI_OBJECT_STRING_BIT.
*
* Use uacpi_object_get_string to retrieve the resulting buffer data.
*/
uacpi_eval_string :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_eval_simple_string :: (parent: *uacpi_namespace_node, path: *uacpi_char, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

/*
* A shorthand for uacpi_eval_typed with UACPI_OBJECT_BUFFER_BIT.
*
* Use uacpi_object_get_buffer to retrieve the resulting buffer data.
*/
uacpi_eval_buffer :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_eval_simple_buffer :: (parent: *uacpi_namespace_node, path: *uacpi_char, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

/*
* A shorthand for uacpi_eval_typed with UACPI_OBJECT_PACKAGE_BIT.
*
* Use uacpi_object_get_package to retrieve the resulting object array.
*/
uacpi_eval_package :: (parent: *uacpi_namespace_node, path: *uacpi_char, args: *uacpi_object_array, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

uacpi_eval_simple_package :: (parent: *uacpi_namespace_node, path: *uacpi_char, ret: **uacpi_object) -> uacpi_status #foreign uacpi;

/*
* Get the bitness of the currently loaded AML code according to the DSDT.
*
* Returns either 32 or 64.
*/
uacpi_get_aml_bitness :: (out_bitness: *uacpi_u8) -> uacpi_status #foreign uacpi;

/*
* Helpers for entering & leaving ACPI mode. Note that ACPI mode is entered
* automatically during the call to uacpi_initialize().
*/
uacpi_enter_acpi_mode :: () -> uacpi_status #foreign uacpi;

/*
* Helpers for entering & leaving ACPI mode. Note that ACPI mode is entered
* automatically during the call to uacpi_initialize().
*/
uacpi_leave_acpi_mode :: () -> uacpi_status #foreign uacpi;

/*
* Attempt to acquire the global lock for 'timeout' milliseconds.
* 0xFFFF implies infinite wait.
*
* On success, 'out_seq' is set to a unique sequence number for the current
* acquire transaction. This number is used for validation during release.
*/
uacpi_acquire_global_lock :: (timeout: uacpi_u16, out_seq: *uacpi_u32) -> uacpi_status #foreign uacpi;
uacpi_release_global_lock :: (seq: uacpi_u32) -> uacpi_status #foreign uacpi;

/*
* Reset the global uACPI state by freeing all internally allocated data
* structures & resetting any global variables. After this call, uACPI must be
* re-initialized from scratch to be used again.
*
* This is called by uACPI automatically if a fatal error occurs during a call
* to uacpi_initialize/uacpi_namespace_load etc. in order to prevent accidental
* use of partially uninitialized subsystems.
*/
uacpi_state_reset :: () -> void #foreign uacpi;

/*
* Set the minimum log level to be accepted by the logging facilities. Any logs
* below this level are discarded and not passed to uacpi_kernel_log, etc.
*
* 0 is treated as a special value that resets the setting to the default value.
*
* E.g. for a log level of UACPI_LOG_INFO:
*   UACPI_LOG_DEBUG -> discarded
*   UACPI_LOG_TRACE -> discarded
*   UACPI_LOG_INFO -> allowed
*   UACPI_LOG_WARN -> allowed
*   UACPI_LOG_ERROR -> allowed
*/
uacpi_context_set_log_level :: (unknown0: uacpi_log_level) -> void #foreign uacpi;

/*
* Enables table checksum validation at installation time instead of first use.
* Note that this makes uACPI map the entire table at once, which not all
* hosts are able to handle at early init.
*/
uacpi_context_set_proactive_table_checksum :: (unknown0: uacpi_bool) -> void #foreign uacpi;

/*
* Set the maximum number of seconds a While loop is allowed to run for before
* getting timed out.
*
* 0 is treated a special value that resets the setting to the default value.
*/
uacpi_context_set_loop_timeout :: (seconds: uacpi_u32) -> void #foreign uacpi;

/*
* Set the maximum call stack depth AML can reach before getting aborted.
*
* 0 is treated as a special value that resets the setting to the default value.
*/
uacpi_context_set_max_call_stack_depth :: (depth: uacpi_u32) -> void #foreign uacpi;

uacpi_context_get_loop_timeout :: () -> uacpi_u32 #foreign uacpi;

uacpi_resource_type :: enum u32 {
    IRQ                     :: 0;
    EXTENDED_IRQ            :: 1;

    DMA                     :: 2;
    FIXED_DMA               :: 3;

    IO                      :: 4;
    FIXED_IO                :: 5;

    ADDRESS16               :: 6;
    ADDRESS32               :: 7;
    ADDRESS64               :: 8;
    ADDRESS64_EXTENDED      :: 9;

    MEMORY24                :: 10;
    MEMORY32                :: 11;
    FIXED_MEMORY32          :: 12;

    START_DEPENDENT         :: 13;
    END_DEPENDENT           :: 14;

    VENDOR_SMALL            :: 15;

    VENDOR_LARGE            :: 16;

    GENERIC_REGISTER        :: 17;
    GPIO_CONNECTION         :: 18;

    SERIAL_I2C_CONNECTION   :: 19;
    SERIAL_SPI_CONNECTION   :: 20;
    SERIAL_UART_CONNECTION  :: 21;
    SERIAL_CSI2_CONNECTION  :: 22;

    PIN_FUNCTION            :: 23;
    PIN_CONFIGURATION       :: 24;
    PIN_GROUP               :: 25;
    PIN_GROUP_FUNCTION      :: 26;
    PIN_GROUP_CONFIGURATION :: 27;

    CLOCK_INPUT             :: 28;

    END_TAG                 :: 29;
    MAX                     :: 29;
}

uacpi_resource_source :: struct {
    index:         uacpi_u8;
    index_present: uacpi_bool;
    length:        uacpi_u16;
    _string:       *uacpi_char;
}

/*
* This applies to IRQ & StartDependent resources only. The DONT_CARE value is
* used for deserialization into the AML format to signify that the serializer
* is allowed to optimize the length down if possible. Note that this is
* generally not allowed unless the resource is generated by the caller:
*
* -- ACPI 6.5 ------------------------------------------------------------
* The resource descriptors in the byte stream argument must be specified
* exactly as listed in the _CRS byte stream - meaning that the identical
* resource descriptors must appear in the identical order, resulting in a
* buffer of exactly the same length. Optimizations such as changing an
* IRQ descriptor to an IRQNoFlags descriptor (or vice-versa) must not be
* performed. Similarly, changing StartDependentFn to StartDependentFnNoPri
* is not allowed.
* ------------------------------------------------------------------------
*/
uacpi_resource_length_kind :: enum u32 {
    DONT_CARE :: 0;
    ONE_LESS  :: 1;
    FULL      :: 2;
}

uacpi_resource_irq :: struct {
    length_kind:     uacpi_u8;
    triggering:      uacpi_u8;
    polarity:        uacpi_u8;
    sharing:         uacpi_u8;
    wake_capability: uacpi_u8;
    num_irqs:        uacpi_u8;
//     irqs:            *uacpi_u8;// Incomplete array in C (zero-sized)
}

uacpi_resource_extended_irq :: struct {
    direction:       uacpi_u8;
    triggering:      uacpi_u8;
    polarity:        uacpi_u8;
    sharing:         uacpi_u8;
    wake_capability: uacpi_u8;
    num_irqs:        uacpi_u8;
    source:          uacpi_resource_source;
//     irqs:            *uacpi_u32;// Incomplete array in C (zero-sized)
}

uacpi_resource_dma :: struct {
    transfer_type:     uacpi_u8;
    bus_master_status: uacpi_u8;
    channel_speed:     uacpi_u8;
    num_channels:      uacpi_u8;
//     channels:          *uacpi_u8;// Incomplete array in C (zero-sized)
}

uacpi_resource_fixed_dma :: struct {
    request_line:   uacpi_u16;
    channel:        uacpi_u16;
    transfer_width: uacpi_u8;
}

uacpi_resource_io :: struct {
    decode_type: uacpi_u8;
    minimum:     uacpi_u16;
    maximum:     uacpi_u16;
    alignment:   uacpi_u8;
    length:      uacpi_u8;
}

uacpi_resource_fixed_io :: struct {
    address: uacpi_u16;
    length:  uacpi_u8;
}

uacpi_memory_attribute :: struct {
    write_status: uacpi_u8;
    caching:      uacpi_u8;
    range_type:   uacpi_u8;
    translation:  uacpi_u8;
}

uacpi_io_attribute :: struct {
    range_type:       uacpi_u8;
    translation:      uacpi_u8;
    translation_type: uacpi_u8;
}

uacpi_address_attribute :: union {
    memory:        uacpi_memory_attribute;
    io:            uacpi_io_attribute;
    type_specific: uacpi_u8;
}

uacpi_resource_address_common :: struct {
    attribute:         uacpi_address_attribute;
    type:              uacpi_u8;
    direction:         uacpi_u8;
    decode_type:       uacpi_u8;
    fixed_min_address: uacpi_u8;
    fixed_max_address: uacpi_u8;
}

uacpi_resource_address16 :: struct {
    common:             uacpi_resource_address_common;
    granularity:        uacpi_u16;
    minimum:            uacpi_u16;
    maximum:            uacpi_u16;
    translation_offset: uacpi_u16;
    address_length:     uacpi_u16;
    source:             uacpi_resource_source;
}

uacpi_resource_address32 :: struct {
    common:             uacpi_resource_address_common;
    granularity:        uacpi_u32;
    minimum:            uacpi_u32;
    maximum:            uacpi_u32;
    translation_offset: uacpi_u32;
    address_length:     uacpi_u32;
    source:             uacpi_resource_source;
}

uacpi_resource_address64 :: struct {
    common:             uacpi_resource_address_common;
    granularity:        uacpi_u64;
    minimum:            uacpi_u64;
    maximum:            uacpi_u64;
    translation_offset: uacpi_u64;
    address_length:     uacpi_u64;
    source:             uacpi_resource_source;
}

uacpi_resource_address64_extended :: struct {
    common:             uacpi_resource_address_common;
    revision_id:        uacpi_u8;
    granularity:        uacpi_u64;
    minimum:            uacpi_u64;
    maximum:            uacpi_u64;
    translation_offset: uacpi_u64;
    address_length:     uacpi_u64;
    attributes:         uacpi_u64;
}

uacpi_resource_memory24 :: struct {
    write_status: uacpi_u8;
    minimum:      uacpi_u16;
    maximum:      uacpi_u16;
    alignment:    uacpi_u16;
    length:       uacpi_u16;
}

uacpi_resource_memory32 :: struct {
    write_status: uacpi_u8;
    minimum:      uacpi_u32;
    maximum:      uacpi_u32;
    alignment:    uacpi_u32;
    length:       uacpi_u32;
}

uacpi_resource_fixed_memory32 :: struct {
    write_status: uacpi_u8;
    address:      uacpi_u32;
    length:       uacpi_u32;
}

uacpi_resource_start_dependent :: struct {
    length_kind:   uacpi_u8;
    compatibility: uacpi_u8;
    performance:   uacpi_u8;
}

uacpi_resource_vendor_defined :: struct {
    length: uacpi_u8;
//     data:   *uacpi_u8;// Incomplete array in C (zero-sized)
}

uacpi_resource_vendor :: uacpi_resource_vendor_defined;

uacpi_resource_vendor_typed :: struct {
    length:   uacpi_u16;
    sub_type: uacpi_u8;
    uuid:     [16] uacpi_u8;
//     data:     *uacpi_u8;// Incomplete array in C (zero-sized)
}

uacpi_resource_generic_register :: struct {
    address_space_id: uacpi_u8;
    bit_width:        uacpi_u8;
    bit_offset:       uacpi_u8;
    access_size:      uacpi_u8;
    address:          uacpi_u64;
}

uacpi_interrupt_connection_flags :: struct {
    triggering:      uacpi_u8;
    polarity:        uacpi_u8;
    sharing:         uacpi_u8;
    wake_capability: uacpi_u8;
}

uacpi_io_connection_flags :: struct {
    restriction: uacpi_u8;
    sharing:     uacpi_u8;
}

uacpi_resource_gpio_connection :: struct {
    revision_id:        uacpi_u8;
    type:               uacpi_u8;
    direction:          uacpi_u8;

    union {
        intr:          uacpi_interrupt_connection_flags;
        io:            uacpi_io_connection_flags;
        type_specific: uacpi_u16;
    }

    pull_configuration: uacpi_u8;
    drive_strength:     uacpi_u16;
    debounce_timeout:   uacpi_u16;
    vendor_data_length: uacpi_u16;
    pin_table_length:   uacpi_u16;
    source:             uacpi_resource_source;
    pin_table:          *uacpi_u16;
    vendor_data:        *uacpi_u8;
}

uacpi_resource_serial_bus_common :: struct {
    revision_id:        uacpi_u8;
    type:               uacpi_u8;
    mode:               uacpi_u8;
    direction:          uacpi_u8;
    sharing:            uacpi_u8;
    type_revision_id:   uacpi_u8;
    type_data_length:   uacpi_u16;
    vendor_data_length: uacpi_u16;
    source:             uacpi_resource_source;
    vendor_data:        *uacpi_u8;
}

uacpi_resource_i2c_connection :: struct {
    common:           uacpi_resource_serial_bus_common;
    addressing_mode:  uacpi_u8;
    slave_address:    uacpi_u16;
    connection_speed: uacpi_u32;
}

uacpi_resource_spi_connection :: struct {
    common:           uacpi_resource_serial_bus_common;
    wire_mode:        uacpi_u8;
    device_polarity:  uacpi_u8;
    data_bit_length:  uacpi_u8;
    phase:            uacpi_u8;
    polarity:         uacpi_u8;
    device_selection: uacpi_u16;
    connection_speed: uacpi_u32;
}

uacpi_resource_uart_connection :: struct {
    common:        uacpi_resource_serial_bus_common;
    stop_bits:     uacpi_u8;
    data_bits:     uacpi_u8;
    endianness:    uacpi_u8;
    parity:        uacpi_u8;
    lines_enabled: uacpi_u8;
    flow_control:  uacpi_u8;
    baud_rate:     uacpi_u32;
    rx_fifo:       uacpi_u16;
    tx_fifo:       uacpi_u16;
}

uacpi_resource_csi2_connection :: struct {
    common:     uacpi_resource_serial_bus_common;
    phy_type:   uacpi_u8;
    local_port: uacpi_u8;
}

uacpi_resource_pin_function :: struct {
    revision_id:        uacpi_u8;
    sharing:            uacpi_u8;
    pull_configuration: uacpi_u8;
    function_number:    uacpi_u16;
    pin_table_length:   uacpi_u16;
    vendor_data_length: uacpi_u16;
    source:             uacpi_resource_source;
    pin_table:          *uacpi_u16;
    vendor_data:        *uacpi_u8;
}

uacpi_resource_pin_configuration :: struct {
    revision_id:        uacpi_u8;
    sharing:            uacpi_u8;
    direction:          uacpi_u8;
    type:               uacpi_u8;
    value:              uacpi_u32;
    pin_table_length:   uacpi_u16;
    vendor_data_length: uacpi_u16;
    source:             uacpi_resource_source;
    pin_table:          *uacpi_u16;
    vendor_data:        *uacpi_u8;
}

uacpi_resource_label :: struct {
    length:  uacpi_u16;
    _string: *uacpi_char;
}

uacpi_resource_pin_group :: struct {
    revision_id:        uacpi_u8;
    direction:          uacpi_u8;
    pin_table_length:   uacpi_u16;
    vendor_data_length: uacpi_u16;
    label:              uacpi_resource_label;
    pin_table:          *uacpi_u16;
    vendor_data:        *uacpi_u8;
}

uacpi_resource_pin_group_function :: struct {
    revision_id:        uacpi_u8;
    sharing:            uacpi_u8;
    direction:          uacpi_u8;
    function:           uacpi_u16;
    vendor_data_length: uacpi_u16;
    source:             uacpi_resource_source;
    label:              uacpi_resource_label;
    vendor_data:        *uacpi_u8;
}

uacpi_resource_pin_group_configuration :: struct {
    revision_id:        uacpi_u8;
    sharing:            uacpi_u8;
    direction:          uacpi_u8;
    type:               uacpi_u8;
    value:              uacpi_u32;
    vendor_data_length: uacpi_u16;
    source:             uacpi_resource_source;
    label:              uacpi_resource_label;
    vendor_data:        *uacpi_u8;
}

uacpi_resource_clock_input :: struct {
    revision_id: uacpi_u8;
    frequency:   uacpi_u8;
    scale:       uacpi_u8;
    divisor:     uacpi_u16;
    numerator:   uacpi_u32;
    source:      uacpi_resource_source;
}

uacpi_resource :: struct {
    type:   uacpi_u32;
    length: uacpi_u32;

    union {
        irq:                     uacpi_resource_irq;
        extended_irq:            uacpi_resource_extended_irq;
        dma:                     uacpi_resource_dma;
        fixed_dma:               uacpi_resource_fixed_dma;
        io:                      uacpi_resource_io;
        fixed_io:                uacpi_resource_fixed_io;
        address16:               uacpi_resource_address16;
        address32:               uacpi_resource_address32;
        address64:               uacpi_resource_address64;
        address64_extended:      uacpi_resource_address64_extended;
        memory24:                uacpi_resource_memory24;
        memory32:                uacpi_resource_memory32;
        fixed_memory32:          uacpi_resource_fixed_memory32;
        start_dependent:         uacpi_resource_start_dependent;
        vendor:                  uacpi_resource_vendor;
        vendor_typed:            uacpi_resource_vendor_typed;
        generic_register:        uacpi_resource_generic_register;
        gpio_connection:         uacpi_resource_gpio_connection;
        serial_bus_common:       uacpi_resource_serial_bus_common;
        i2c_connection:          uacpi_resource_i2c_connection;
        spi_connection:          uacpi_resource_spi_connection;
        uart_connection:         uacpi_resource_uart_connection;
        csi2_connection:         uacpi_resource_csi2_connection;
        pin_function:            uacpi_resource_pin_function;
        pin_configuration:       uacpi_resource_pin_configuration;
        pin_group:               uacpi_resource_pin_group;
        pin_group_function:      uacpi_resource_pin_group_function;
        pin_group_configuration: uacpi_resource_pin_group_configuration;
        clock_input:             uacpi_resource_clock_input;
    }
}

uacpi_resources :: struct {
    /*
    * Length of the 'entries' array in BYTES (NOT the count of resources),
    * see comment above 'entries' for more information.
    */
    length:  uacpi_size;

    /*
    * Resources are variable length! See UACPI_NEXT_RESOURCE to see how to
    * retrieve the next resource. You can alternatively use
    * uacpi_for_each_resource instead of iterating manually.
    *
    * Resources are guaranteed to be naturally aligned and are always
    * terminated by a resource of type UACPI_RESOURCE_TYPE_END_TAG.
    */
    entries: *uacpi_resource;
}

uacpi_free_resources :: (unknown0: *uacpi_resources) -> void #foreign uacpi;

uacpi_resource_iteration_callback :: #type (user: *void, resource: *uacpi_resource) -> uacpi_iteration_decision #c_call;

/*
* Evaluate the _CRS method for a 'device' and get the returned resource list
* via 'out_resources'.
*
* NOTE: the returned buffer must be released via uacpi_free_resources()
*
* If you don't need to keep the resource array for later use you can
* uacpi_for_each_device_resource(device, "_CRS", ...) instead, which takes
* care of iteration & memory management on its own.
*/
uacpi_get_current_resources :: (device: *uacpi_namespace_node, out_resources: **uacpi_resources) -> uacpi_status #foreign uacpi;

/*
* Evaluate the _PRS method for a 'device' and get the returned resource list
* via 'out_resources'.
*
* NOTE: the returned buffer must be released via uacpi_free_resources()
*
* If you don't need to keep the resource array for later use you can
* uacpi_for_each_device_resource(device, "_PRS", ...) instead, which takes
* care of iteration & memory management on its own.
*/
uacpi_get_possible_resources :: (device: *uacpi_namespace_node, out_resources: **uacpi_resources) -> uacpi_status #foreign uacpi;

/*
* Evaluate an arbitrary method that is expected to return an AML resource
* buffer for a 'device' and get the returned resource list via 'out_resources'.
*
* NOTE: the returned buffer must be released via uacpi_free_resources()
*
* If you don't need to keep the resource array for later use you can
* uacpi_for_each_device_resource(device, method, ...) instead, which takes
* care of iteration & memory management on its own.
*/
uacpi_get_device_resources :: (device: *uacpi_namespace_node, method: *uacpi_char, out_resources: **uacpi_resources) -> uacpi_status #foreign uacpi;

/*
* Set the configuration to be used by the 'device' by calling its _SRS method.
*
* Note that this expects 'resources' in the normal 'uacpi_resources' format,
* and not the raw AML resources bytestream, the conversion to the latter is
* done automatically by this API. If you want to _SRS a raw AML resources
* bytestream, use 'uacpi_execute' or similar API directly.
*/
uacpi_set_resources :: (device: *uacpi_namespace_node, resources: *uacpi_resources) -> uacpi_status #foreign uacpi;

/*
* A convenience helper for iterating over the resource list returned by any
* of the uacpi_get_*_resources functions.
*/
uacpi_for_each_resource :: (resources: *uacpi_resources, cb: uacpi_resource_iteration_callback, user: *void) -> uacpi_status #foreign uacpi;

/*
* A shorthand for uacpi_get_device_resources() + uacpi_for_each_resource().
*
* Use if you don't actually want to save the 'resources' list, but simply want
* to iterate it once to extract the resources you care about and then free it
* right away.
*/
uacpi_for_each_device_resource :: (device: *uacpi_namespace_node, method: *uacpi_char, cb: uacpi_resource_iteration_callback, user: *void) -> uacpi_status #foreign uacpi;

/*
* Convert a single AML-encoded resource to native format.
*
* This should be used for converting Connection() fields (passed during IO on
* GeneralPurposeIO or GenericSerialBus operation regions) or other similar
* buffers with only one resource to native format.
*
* NOTE: the returned buffer must be released via uacpi_free_resource()
*/
uacpi_get_resource_from_buffer :: (aml_buffer: uacpi_data_view, out_resource: **uacpi_resource) -> uacpi_status #foreign uacpi;

uacpi_free_resource :: (unknown0: *uacpi_resource) -> void #foreign uacpi;

/*
* Install a Notify() handler to a device node.
* A handler installed to the root node will receive all notifications, even if
* a device already has a dedicated Notify handler.
* 'handler_context' is passed to the handler on every invocation.
*/
uacpi_install_notify_handler :: (node: *uacpi_namespace_node, handler: uacpi_notify_handler, handler_context: uacpi_handle) -> uacpi_status #foreign uacpi;

uacpi_uninstall_notify_handler :: (node: *uacpi_namespace_node, handler: uacpi_notify_handler) -> uacpi_status #foreign uacpi;

uacpi_table_identifiers :: struct {
    signature:    uacpi_object_name;

    // if oemid[0] == 0 this field is ignored
    oemid:        [6] u8;

    // if oem_table_id[0] == 0 this field is ignored
    oem_table_id: [8] u8;
}

uacpi_table :: struct {
    union {
        virt_addr: uacpi_virt_addr;
        ptr:       *void;
        hdr:       *acpi_sdt_hdr;
    }

    // Index number used to identify this table internally
    index: uacpi_size;
}

/*
* Install a table from either a virtual or a physical address.
* The table is simply stored in the internal table array, and not loaded by
* the interpreter (see uacpi_table_load).
*
* The table is optionally returned via 'out_table'.
*
* Manual calls to uacpi_table_install are not subject to filtering via the
* table installation callback (if any).
*/
uacpi_table_install :: (unknown0: *void, out_table: *uacpi_table) -> uacpi_status #foreign uacpi;

uacpi_table_install_physical :: (unknown0: uacpi_phys_addr, out_table: *uacpi_table) -> uacpi_status #foreign uacpi;

/*
* Load a previously installed table by feeding it to the interpreter.
*/
uacpi_table_load :: (index: uacpi_size) -> uacpi_status #foreign uacpi;

/*
* Helpers for finding tables.
*
* for find_by_signature:
*     'signature' is an array of 4 characters, a null terminator is not
*     necessary and can be omitted (especially useful for non-C language
*     bindings)
*
* 'out_table' is a pointer to a caller allocated uacpi_table structure that
* receives the table pointer & its internal index in case the call was
* successful.
*
* NOTE:
* The returned table's reference count is incremented by 1, which keeps its
* mapping alive forever unless uacpi_table_unref() is called for this table
* later on. Calling uacpi_table_find_next_with_same_signature() on a table also
* drops its reference count by 1, so if you want to keep it mapped you must
* manually call uacpi_table_ref() beforehand.
*/
uacpi_table_find_by_signature :: (signature: *uacpi_char, out_table: *uacpi_table) -> uacpi_status #foreign uacpi;

uacpi_table_find_next_with_same_signature :: (in_out_table: *uacpi_table) -> uacpi_status #foreign uacpi;

uacpi_table_find :: (id: *uacpi_table_identifiers, out_table: *uacpi_table) -> uacpi_status #foreign uacpi;

/*
* Increment/decrement a table's reference count.
* The table is unmapped when the reference count drops to 0.
*/
uacpi_table_ref :: (unknown0: *uacpi_table) -> uacpi_status #foreign uacpi;
uacpi_table_unref :: (unknown0: *uacpi_table) -> uacpi_status #foreign uacpi;

/*
* Returns the pointer to a sanitized internal version of FADT.
*
* The revision is guaranteed to be correct. All of the registers are converted
* to GAS format. Fields that might contain garbage are cleared.
*/
uacpi_table_fadt :: (unknown0: **acpi_fadt) -> uacpi_status #foreign uacpi;

uacpi_table_installation_disposition :: enum u32 {
    ALLOW             :: 0;

    DENY              :: 1;

    VIRTUAL_OVERRIDE  :: 2;

    PHYSICAL_OVERRIDE :: 3;
}

uacpi_table_installation_handler :: #type (hdr: *acpi_sdt_hdr, out_override_address: *uacpi_u64) -> uacpi_table_installation_disposition #c_call;

/*
* Set a handler that is invoked for each table before it gets installed.
*
* Depending on the return value, the table is either allowed to be installed
* as-is, denied, or overriden with a new one.
*/
uacpi_set_table_installation_handler :: (handler: uacpi_table_installation_handler) -> uacpi_status #foreign uacpi;

uacpi_subtable_iteration_callback :: #type (unknown0: uacpi_handle, unknown1: *acpi_entry_hdr) -> uacpi_iteration_decision #c_call;

/*
* Iterate every subtable of a table such as MADT or SRAT.
*
* 'hdr' is the pointer to the main table, 'hdr_size' is the number of bytes in
* the table before the beginning of the subtable records. 'cb' is the callback
* invoked for each subtable with the 'user' context pointer passed for every
* invocation.
*
* Example usage:
*    uacpi_table tbl;
*
*    uacpi_table_find_by_signature(ACPI_MADT_SIGNATURE, &tbl);
*    uacpi_for_each_subtable(
*        tbl.hdr, sizeof(struct acpi_madt), parse_madt, NULL
*    );
*/
uacpi_for_each_subtable :: (hdr: *acpi_sdt_hdr, hdr_size: u64, cb: uacpi_subtable_iteration_callback, user: *void) -> uacpi_status #foreign uacpi;

uacpi_register :: enum u32 {
    PM1_STS :: 0;
    PM1_EN  :: 1;
    PM1_CNT :: 2;
    PM_TMR  :: 3;
    PM2_CNT :: 4;
    SLP_CNT :: 5;
    SLP_STS :: 6;
    RESET   :: 7;
    SMI_CMD :: 8;
    MAX     :: 8;
}

/*
* Read a register from FADT
*
* NOTE: write-only bits (if any) are cleared automatically
*/
uacpi_read_register :: (unknown0: uacpi_register, unknown1: *uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* Write a register from FADT
*
* NOTE:
* - Preserved bits (if any) are preserved automatically
* - If a register is made up of two (e.g. PM1a and PM1b) parts, the input
*   is written to both at the same time
*/
uacpi_write_register :: (unknown0: uacpi_register, unknown1: uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* Write a register from FADT
*
* NOTE:
* - Preserved bits (if any) are preserved automatically
* - For registers that are made up of two (e.g. PM1a and PM1b) parts, the
*   provided values are written to their respective physical register
*/
uacpi_write_registers :: (unknown0: uacpi_register, unknown1: uacpi_u64, unknown2: uacpi_u64) -> uacpi_status #foreign uacpi;

uacpi_register_field :: enum u32 {
    TMR_STS         :: 0;
    BM_STS          :: 1;
    GBL_STS         :: 2;
    PWRBTN_STS      :: 3;
    SLPBTN_STS      :: 4;
    RTC_STS         :: 5;
    PCIEX_WAKE_STS  :: 6;
    HWR_WAK_STS     :: 7;
    WAK_STS         :: 8;
    TMR_EN          :: 9;
    GBL_EN          :: 10;
    PWRBTN_EN       :: 11;
    SLPBTN_EN       :: 12;
    RTC_EN          :: 13;
    PCIEXP_WAKE_DIS :: 14;
    SCI_EN          :: 15;
    BM_RLD          :: 16;
    GBL_RLS         :: 17;
    SLP_TYP         :: 18;
    HWR_SLP_TYP     :: 19;
    SLP_EN          :: 20;
    HWR_SLP_EN      :: 21;
    ARB_DIS         :: 22;
    MAX             :: 22;
}

/*
* Read a field from a FADT register
*
* NOTE: The value is automatically masked and shifted down as appropriate,
*       the client code doesn't have to do any bit manipulation. E.g. for
*       a field at 0b???XX??? the returned value will contain just the 0bXX
*/
uacpi_read_register_field :: (unknown0: uacpi_register_field, unknown1: *uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* Write to a field of a FADT register
*
* NOTE: The value is automatically masked and shifted up as appropriate,
*       the client code doesn't have to do any bit manipulation. E.g. for
*       a field at 0b???XX??? the passed value should be just 0bXX
*/
uacpi_write_register_field :: (unknown0: uacpi_register_field, unknown1: uacpi_u64) -> uacpi_status #foreign uacpi;

/*
* Install an address space handler to a device node.
* The handler is recursively connected to all of the operation regions of
* type 'space' underneath 'device_node'. Note that this recursion stops as
* soon as another device node that already has an address space handler of
* this type installed is encountered.
*/
uacpi_install_address_space_handler :: (device_node: *uacpi_namespace_node, space: uacpi_address_space, handler: uacpi_region_handler, handler_context: uacpi_handle) -> uacpi_status #foreign uacpi;

/*
* Uninstall the handler of type 'space' from a given device node.
*/
uacpi_uninstall_address_space_handler :: (device_node: *uacpi_namespace_node, space: uacpi_address_space) -> uacpi_status #foreign uacpi;

/*
* Execute _REG(space, ACPI_REG_CONNECT) for all of the opregions with this
* address space underneath this device. This should only be called manually
* if you want to register an early handler that must be available before the
* call to uacpi_namespace_initialize().
*/
uacpi_reg_all_opregions :: (device_node: *uacpi_namespace_node, space: uacpi_address_space) -> uacpi_status #foreign uacpi;

acpi_gas :: struct {
    address_space_id:    uacpi_u8;
    register_bit_width:  uacpi_u8;
    register_bit_offset: uacpi_u8;
    access_size:         uacpi_u8;
    address:             uacpi_u64 #align 1;
}

acpi_rsdp :: struct {
    signature:         [8] uacpi_char;
    checksum:          uacpi_u8;
    oemid:             [6] uacpi_char;
    revision:          uacpi_u8;
    rsdt_addr:         uacpi_u32 #align 1;
    length:            uacpi_u32 #align 1; // vvvv available if .revision >= 2.0 only
    xsdt_addr:         uacpi_u64 #align 1;
    extended_checksum: uacpi_u8;
    rsvd:              [3] uacpi_u8;
}

acpi_sdt_hdr :: struct {
    signature:        [4] uacpi_char;
    length:           uacpi_u32 #align 1;
    revision:         uacpi_u8;
    checksum:         uacpi_u8;
    oemid:            [6] uacpi_char;
    oem_table_id:     [8] uacpi_char;
    oem_revision:     uacpi_u32 #align 1;
    creator_id:       uacpi_u32 #align 1;
    creator_revision: uacpi_u32 #align 1;
}

acpi_rsdt :: struct {
    hdr:     acpi_sdt_hdr;
//     entries: *uacpi_u32 #align 1;// Incomplete array in C (zero-sized)
}

acpi_xsdt :: struct {
    hdr:     acpi_sdt_hdr;
//     entries: *uacpi_u64 #align 1;// Incomplete array in C (zero-sized)
}

acpi_entry_hdr :: struct {
    /*
    * - acpi_madt_entry_type for the APIC table
    * - acpi_srat_entry_type for the SRAT table
    */
    type:   uacpi_u8;
    length: uacpi_u8;
}

acpi_madt_entry_type :: enum u32 {
    LAPIC                      :: 0;
    IOAPIC                     :: 1;
    INTERRUPT_SOURCE_OVERRIDE  :: 2;
    NMI_SOURCE                 :: 3;
    LAPIC_NMI                  :: 4;
    LAPIC_ADDRESS_OVERRIDE     :: 5;
    IOSAPIC                    :: 6;
    LSAPIC                     :: 7;
    PLATFORM_INTERRUPT_SOURCES :: 8;
    LOCAL_X2APIC               :: 9;
    LOCAL_X2APIC_NMI           :: 10;
    GICC                       :: 11;
    GICD                       :: 12;
    GIC_MSI_FRAME              :: 13;
    GICR                       :: 14;
    GIC_ITS                    :: 15;
    MULTIPROCESSOR_WAKEUP      :: 16;
    CORE_PIC                   :: 17;
    LIO_PIC                    :: 18;
    HT_PIC                     :: 19;
    EIO_PIC                    :: 20;
    MSI_PIC                    :: 21;
    BIO_PIC                    :: 22;
    LPC_PIC                    :: 23;
    RINTC                      :: 24;
    IMSIC                      :: 25;
    APLIC                      :: 26;
    PLIC                       :: 27;
    RESERVED                   :: 28;
    OEM                        :: 128;
}

acpi_madt :: struct {
    hdr:                                acpi_sdt_hdr;
    local_interrupt_controller_address: uacpi_u32 #align 1;
    flags:                              uacpi_u32 #align 1;
//     entries:                            *acpi_entry_hdr;// Incomplete array in C (zero-sized)
}

acpi_madt_lapic :: struct {
    hdr:   acpi_entry_hdr;
    uid:   uacpi_u8;
    id:    uacpi_u8;
    flags: uacpi_u32 #align 1;
}

acpi_madt_ioapic :: struct {
    hdr:      acpi_entry_hdr;
    id:       uacpi_u8;
    rsvd:     uacpi_u8;
    address:  uacpi_u32 #align 1;
    gsi_base: uacpi_u32 #align 1;
}

acpi_madt_interrupt_source_override :: struct {
    hdr:    acpi_entry_hdr;
    bus:    uacpi_u8;
    source: uacpi_u8;
    gsi:    uacpi_u32 #align 1;
    flags:  uacpi_u16 #align 1;
}

acpi_madt_nmi_source :: struct {
    hdr:   acpi_entry_hdr;
    flags: uacpi_u16 #align 1;
    gsi:   uacpi_u32 #align 1;
}

acpi_madt_lapic_nmi :: struct {
    hdr:   acpi_entry_hdr;
    uid:   uacpi_u8;
    flags: uacpi_u16 #align 1;
    lint:  uacpi_u8;
}

acpi_madt_lapic_address_override :: struct {
    hdr:     acpi_entry_hdr;
    rsvd:    uacpi_u16 #align 1;
    address: uacpi_u64 #align 1;
}

acpi_madt_iosapic :: struct {
    hdr:      acpi_entry_hdr;
    id:       uacpi_u8;
    rsvd:     uacpi_u8;
    gsi_base: uacpi_u32 #align 1;
    address:  uacpi_u64 #align 1;
}

acpi_madt_lsapic :: struct {
    hdr:        acpi_entry_hdr;
    acpi_id:    uacpi_u8;
    id:         uacpi_u8;
    eid:        uacpi_u8;
    reserved:   [3] uacpi_u8;
    flags:      uacpi_u32 #align 1;
    uid:        uacpi_u32 #align 1;
//     uid_string: *uacpi_char;// Incomplete array in C (zero-sized)
}

acpi_madt_platform_interrupt_source :: struct {
    hdr:            acpi_entry_hdr;
    flags:          uacpi_u16 #align 1;
    type:           uacpi_u8;
    processor_id:   uacpi_u8;
    processor_eid:  uacpi_u8;
    iosapic_vector: uacpi_u8;
    gsi:            uacpi_u32 #align 1;
    platform_flags: uacpi_u32 #align 1;
}

acpi_madt_x2apic :: struct {
    hdr:   acpi_entry_hdr;
    rsvd:  uacpi_u16 #align 1;
    id:    uacpi_u32 #align 1;
    flags: uacpi_u32 #align 1;
    uid:   uacpi_u32 #align 1;
}

acpi_madt_x2apic_nmi :: struct {
    hdr:      acpi_entry_hdr;
    flags:    uacpi_u16 #align 1;
    uid:      uacpi_u32 #align 1;
    lint:     uacpi_u8;
    reserved: [3] uacpi_u8;
}

acpi_madt_gicc :: struct {
    hdr:                       acpi_entry_hdr;
    rsvd0:                     uacpi_u16 #align 1;
    interface_number:          uacpi_u32 #align 1;
    acpi_id:                   uacpi_u32 #align 1;
    flags:                     uacpi_u32 #align 1;
    parking_protocol_version:  uacpi_u32 #align 1;
    perf_interrupt_gsiv:       uacpi_u32 #align 1;
    parked_address:            uacpi_u64 #align 1;
    address:                   uacpi_u64 #align 1;
    gicv:                      uacpi_u64 #align 1;
    gich:                      uacpi_u64 #align 1;
    vgic_maitenante_interrupt: uacpi_u32 #align 1;
    gicr_base_address:         uacpi_u64 #align 1;
    mpidr:                     uacpi_u64 #align 1;
    power_efficiency_class:    uacpi_u8;
    rsvd1:                     uacpi_u8;
    spe_overflow_interrupt:    uacpi_u16 #align 1;
    trbe_interrupt:            uacpi_u16 #align 1;
}

acpi_madt_gicd :: struct {
    hdr:                acpi_entry_hdr;
    rsvd0:              uacpi_u16 #align 1;
    id:                 uacpi_u32 #align 1;
    address:            uacpi_u64 #align 1;
    system_vector_base: uacpi_u32 #align 1;
    gic_version:        uacpi_u8;
    reserved1:          [3] uacpi_u8;
}

acpi_madt_gic_msi_frame :: struct {
    hdr:       acpi_entry_hdr;
    rsvd:      uacpi_u16 #align 1;
    id:        uacpi_u32 #align 1;
    address:   uacpi_u64 #align 1;
    flags:     uacpi_u32 #align 1;
    spi_count: uacpi_u16 #align 1;
    spi_base:  uacpi_u16 #align 1;
}

acpi_madt_gicr :: struct {
    hdr:     acpi_entry_hdr;
    rsvd:    uacpi_u16 #align 1;
    address: uacpi_u64 #align 1;
    length:  uacpi_u32 #align 1;
}

acpi_madt_gic_its :: struct {
    hdr:     acpi_entry_hdr;
    rsvd0:   uacpi_u16 #align 1;
    id:      uacpi_u32 #align 1;
    address: uacpi_u64 #align 1;
    rsvd1:   uacpi_u32 #align 1;
}

acpi_madt_multiprocessor_wakeup :: struct {
    hdr:             acpi_entry_hdr;
    mailbox_version: uacpi_u16 #align 1;
    rsvd:            uacpi_u32 #align 1;
    mailbox_address: uacpi_u64 #align 1;
}

acpi_madt_core_pic :: struct {
    hdr:     acpi_entry_hdr;
    version: uacpi_u8;
    acpi_id: uacpi_u32 #align 1;
    id:      uacpi_u32 #align 1;
    flags:   uacpi_u32 #align 1;
}

acpi_madt_lio_pic :: struct {
    hdr:                    acpi_entry_hdr;
    version:                uacpi_u8;
    address:                uacpi_u64 #align 1;
    size:                   uacpi_u16 #align 1;
    cascade_vector:         uacpi_u16 #align 1;
    cascade_vector_mapping: uacpi_u64 #align 1;
}

acpi_madt_ht_pic :: struct {
    hdr:            acpi_entry_hdr;
    version:        uacpi_u8;
    address:        uacpi_u64 #align 1;
    size:           uacpi_u16 #align 1;
    cascade_vector: uacpi_u64 #align 1;
}

acpi_madt_eio_pic :: struct {
    hdr:            acpi_entry_hdr;
    version:        uacpi_u8;
    cascade_vector: uacpi_u8;
    node:           uacpi_u8;
    node_map:       uacpi_u64 #align 1;
}

acpi_madt_msi_pic :: struct {
    hdr:     acpi_entry_hdr;
    version: uacpi_u8;
    address: uacpi_u64 #align 1;
    start:   uacpi_u32 #align 1;
    count:   uacpi_u32 #align 1;
}

acpi_madt_bio_pic :: struct {
    hdr:         acpi_entry_hdr;
    version:     uacpi_u8;
    address:     uacpi_u64 #align 1;
    size:        uacpi_u16 #align 1;
    hardware_id: uacpi_u16 #align 1;
    gsi_base:    uacpi_u16 #align 1;
}

acpi_madt_lpc_pic :: struct {
    hdr:            acpi_entry_hdr;
    version:        uacpi_u8;
    address:        uacpi_u64 #align 1;
    size:           uacpi_u16 #align 1;
    cascade_vector: uacpi_u16 #align 1;
}

acpi_madt_rintc :: struct {
    hdr:         acpi_entry_hdr;
    version:     uacpi_u8;
    rsvd:        uacpi_u8;
    flags:       uacpi_u32 #align 1;
    hart_id:     uacpi_u64 #align 1;
    uid:         uacpi_u32 #align 1;
    ext_intc_id: uacpi_u32 #align 1;
    address:     uacpi_u64 #align 1;
    size:        uacpi_u32 #align 1;
}

acpi_madt_imsic :: struct {
    hdr:               acpi_entry_hdr;
    version:           uacpi_u8;
    rsvd:              uacpi_u8;
    flags:             uacpi_u32 #align 1;
    num_ids:           uacpi_u16 #align 1;
    num_guest_ids:     uacpi_u16 #align 1;
    guest_index_bits:  uacpi_u8;
    hart_index_bits:   uacpi_u8;
    group_index_bits:  uacpi_u8;
    group_index_shift: uacpi_u8;
}

acpi_madt_aplic :: struct {
    hdr:           acpi_entry_hdr;
    version:       uacpi_u8;
    id:            uacpi_u8;
    flags:         uacpi_u32 #align 1;
    hardware_id:   uacpi_u64 #align 1;
    idc_count:     uacpi_u16 #align 1;
    sources_count: uacpi_u16 #align 1;
    gsi_base:      uacpi_u32 #align 1;
    address:       uacpi_u64 #align 1;
    size:          uacpi_u32 #align 1;
}

acpi_madt_plic :: struct {
    hdr:           acpi_entry_hdr;
    version:       uacpi_u8;
    id:            uacpi_u8;
    hardware_id:   uacpi_u64 #align 1;
    sources_count: uacpi_u16 #align 1;
    max_priority:  uacpi_u16 #align 1;
    flags:         uacpi_u32 #align 1;
    size:          uacpi_u32 #align 1;
    address:       uacpi_u64 #align 1;
    gsi_base:      uacpi_u32 #align 1;
}

acpi_srat_entry_type :: enum u32 {
    PROCESSOR_AFFINITY         :: 0;
    MEMORY_AFFINITY            :: 1;
    X2APIC_AFFINITY            :: 2;
    GICC_AFFINITY              :: 3;
    GIC_ITS_AFFINITY           :: 4;
    GENERIC_INITIATOR_AFFINITY :: 5;
    GENERIC_PORT_AFFINITY      :: 6;
    RINTC_AFFINITY             :: 7;
}

acpi_srat :: struct {
    hdr:     acpi_sdt_hdr;
    rsvd0:   uacpi_u32 #align 1;
    rsvd1:   uacpi_u64 #align 1;
//     entries: *acpi_entry_hdr;// Incomplete array in C (zero-sized)
}

acpi_srat_processor_affinity :: struct {
    hdr:                   acpi_entry_hdr;
    proximity_domain_low:  uacpi_u8;
    id:                    uacpi_u8;
    flags:                 uacpi_u32 #align 1;
    eid:                   uacpi_u8;
    proximity_domain_high: [3] uacpi_u8;
    clock_domain:          uacpi_u32 #align 1;
}

acpi_srat_memory_affinity :: struct {
    hdr:              acpi_entry_hdr;
    proximity_domain: uacpi_u32 #align 1;
    rsvd0:            uacpi_u16 #align 1;
    address:          uacpi_u64 #align 1;
    length:           uacpi_u64 #align 1;
    rsvd1:            uacpi_u32 #align 1;
    flags:            uacpi_u32 #align 1;
    rsdv2:            uacpi_u64 #align 1;
}

acpi_srat_x2apic_affinity :: struct {
    hdr:              acpi_entry_hdr;
    rsvd0:            uacpi_u16 #align 1;
    proximity_domain: uacpi_u32 #align 1;
    id:               uacpi_u32 #align 1;
    flags:            uacpi_u32 #align 1;
    clock_domain:     uacpi_u32 #align 1;
    rsvd1:            uacpi_u32 #align 1;
}

acpi_srat_gicc_affinity :: struct {
    hdr:              acpi_entry_hdr;
    proximity_domain: uacpi_u32 #align 1;
    uid:              uacpi_u32 #align 1;
    flags:            uacpi_u32 #align 1;
    clock_domain:     uacpi_u32 #align 1;
}

acpi_srat_gic_its_affinity :: struct {
    hdr:              acpi_entry_hdr;
    proximity_domain: uacpi_u32 #align 1;
    rsvd:             uacpi_u16 #align 1;
    id:               uacpi_u32 #align 1;
}

acpi_srat_generic_affinity :: struct {
    hdr:              acpi_entry_hdr;
    rsvd0:            uacpi_u8;
    handle_type:      uacpi_u8;
    proximity_domain: uacpi_u32 #align 1;
    handle:           [16] uacpi_u8;
    flags:            uacpi_u32 #align 1;
    rsvd1:            uacpi_u32 #align 1;
}

acpi_srat_rintc_affinity :: struct {
    hdr:              acpi_entry_hdr;
    rsvd:             uacpi_u16 #align 1;
    proximity_domain: uacpi_u32 #align 1;
    uid:              uacpi_u32 #align 1;
    flags:            uacpi_u32 #align 1;
    clock_domain:     uacpi_u32 #align 1;
}

acpi_slit :: struct {
    hdr:            acpi_sdt_hdr;
    num_localities: uacpi_u64 #align 1;
//     matrix:         *uacpi_u8;// Incomplete array in C (zero-sized)
}

acpi_gtdt :: struct {
    hdr:                   acpi_sdt_hdr;
    cnt_control_base:      uacpi_u64 #align 1;
    rsvd:                  uacpi_u32 #align 1;
    el1_secure_gsiv:       uacpi_u32 #align 1;
    el1_secure_flags:      uacpi_u32 #align 1;
    el1_non_secure_gsiv:   uacpi_u32 #align 1;
    el1_non_secure_flags:  uacpi_u32 #align 1;
    el1_virtual_gsiv:      uacpi_u32 #align 1;
    el1_virtual_flags:     uacpi_u32 #align 1;
    el2_gsiv:              uacpi_u32 #align 1;
    el2_flags:             uacpi_u32 #align 1;
    cnt_read_base:         uacpi_u64 #align 1;
    platform_timer_count:  uacpi_u32 #align 1;
    platform_timer_offset: uacpi_u32 #align 1;
    el2_virtual_gsiv:      uacpi_u32 #align 1; // revision >= 3
    el2_virtual_flags:     uacpi_u32 #align 1;
}

acpi_gtdt_entry_type :: enum u32 {
    TIMER    :: 0;
    WATCHDOG :: 1;
}

acpi_gtdt_entry_hdr :: struct {
    type:   uacpi_u8;
    length: uacpi_u16 #align 1;
}

acpi_gtdt_timer :: struct {
    hdr:          acpi_gtdt_entry_hdr;
    rsvd:         uacpi_u8;
    cnt_ctl_base: uacpi_u64 #align 1;
    timer_count:  uacpi_u32 #align 1;
    timer_offset: uacpi_u32 #align 1;
}

acpi_gtdt_timer_entry :: struct {
    frame_number:   uacpi_u8;
    rsvd:           [3] uacpi_u8;
    cnt_base:       uacpi_u64 #align 1;
    el0_cnt_base:   uacpi_u64 #align 1;
    physical_gsiv:  uacpi_u32 #align 1;
    physical_flags: uacpi_u32 #align 1;
    virtual_gsiv:   uacpi_u32 #align 1;
    virtual_flags:  uacpi_u32 #align 1;
    common_flags:   uacpi_u32 #align 1;
}

acpi_gtdt_watchdog :: struct {
    hdr:           acpi_gtdt_entry_hdr;
    rsvd:          uacpi_u8;
    refresh_frame: uacpi_u64 #align 1;
    control_frame: uacpi_u64 #align 1;
    gsiv:          uacpi_u32 #align 1;
    flags:         uacpi_u32 #align 1;
}

// Forward-declared to avoid including the entire acpi.h here
acpi_fadt :: struct {
    hdr:                        acpi_sdt_hdr;
    firmware_ctrl:              uacpi_u32 #align 1;
    dsdt:                       uacpi_u32 #align 1;
    int_model:                  uacpi_u8;
    preferred_pm_profile:       uacpi_u8;
    sci_int:                    uacpi_u16 #align 1;
    smi_cmd:                    uacpi_u32 #align 1;
    acpi_enable:                uacpi_u8;
    acpi_disable:               uacpi_u8;
    s4bios_req:                 uacpi_u8;
    pstate_cnt:                 uacpi_u8;
    pm1a_evt_blk:               uacpi_u32 #align 1;
    pm1b_evt_blk:               uacpi_u32 #align 1;
    pm1a_cnt_blk:               uacpi_u32 #align 1;
    pm1b_cnt_blk:               uacpi_u32 #align 1;
    pm2_cnt_blk:                uacpi_u32 #align 1;
    pm_tmr_blk:                 uacpi_u32 #align 1;
    gpe0_blk:                   uacpi_u32 #align 1;
    gpe1_blk:                   uacpi_u32 #align 1;
    pm1_evt_len:                uacpi_u8;
    pm1_cnt_len:                uacpi_u8;
    pm2_cnt_len:                uacpi_u8;
    pm_tmr_len:                 uacpi_u8;
    gpe0_blk_len:               uacpi_u8;
    gpe1_blk_len:               uacpi_u8;
    gpe1_base:                  uacpi_u8;
    cst_cnt:                    uacpi_u8;
    p_lvl2_lat:                 uacpi_u16 #align 1;
    p_lvl3_lat:                 uacpi_u16 #align 1;
    flush_size:                 uacpi_u16 #align 1;
    flush_stride:               uacpi_u16 #align 1;
    duty_offset:                uacpi_u8;
    duty_width:                 uacpi_u8;
    day_alrm:                   uacpi_u8;
    mon_alrm:                   uacpi_u8;
    century:                    uacpi_u8;
    iapc_boot_arch:             uacpi_u16 #align 1;
    rsvd:                       uacpi_u8;
    flags:                      uacpi_u32 #align 1;
    reset_reg:                  acpi_gas;
    reset_value:                uacpi_u8;
    arm_boot_arch:              uacpi_u16 #align 1;
    fadt_minor_verison:         uacpi_u8;
    x_firmware_ctrl:            uacpi_u64 #align 1;
    x_dsdt:                     uacpi_u64 #align 1;
    x_pm1a_evt_blk:             acpi_gas;
    x_pm1b_evt_blk:             acpi_gas;
    x_pm1a_cnt_blk:             acpi_gas;
    x_pm1b_cnt_blk:             acpi_gas;
    x_pm2_cnt_blk:              acpi_gas;
    x_pm_tmr_blk:               acpi_gas;
    x_gpe0_blk:                 acpi_gas;
    x_gpe1_blk:                 acpi_gas;
    sleep_control_reg:          acpi_gas;
    sleep_status_reg:           acpi_gas;
    hypervisor_vendor_identity: uacpi_u64 #align 1;
}

acpi_facs :: struct {
    signature:                [4] uacpi_char;
    length:                   uacpi_u32;
    hardware_signature:       uacpi_u32;
    firmware_waking_vector:   uacpi_u32;
    global_lock:              uacpi_u32;
    flags:                    uacpi_u32;
    x_firmware_waking_vector: uacpi_u64;
    version:                  uacpi_u8;
    rsvd0:                    [3] uacpi_char;
    ospm_flags:               uacpi_u32;
    rsvd1:                    [24] uacpi_char;
}

acpi_mcfg_allocation :: struct {
    address:   uacpi_u64 #align 1;
    segment:   uacpi_u16 #align 1;
    start_bus: uacpi_u8;
    end_bus:   uacpi_u8;
    rsvd:      uacpi_u32 #align 1;
}

acpi_mcfg :: struct {
    hdr:     acpi_sdt_hdr;
    rsvd:    uacpi_u64 #align 1;
//     entries: *acpi_mcfg_allocation;// Incomplete array in C (zero-sized)
}

acpi_hpet :: struct {
    hdr:            acpi_sdt_hdr;
    block_id:       uacpi_u32 #align 1;
    address:        acpi_gas;
    number:         uacpi_u8;
    min_clock_tick: uacpi_u16 #align 1;
    flags:          uacpi_u8;
}

acpi_dsdt :: struct {
    hdr:              acpi_sdt_hdr;
//     definition_block: *uacpi_u8;// Incomplete array in C (zero-sized)
}

acpi_ssdt :: struct {
    hdr:              acpi_sdt_hdr;
//     definition_block: *uacpi_u8;// Incomplete array in C (zero-sized)
}

acpi_ecdt :: struct {
    hdr:        acpi_sdt_hdr;
    ec_control: acpi_gas;
    ec_data:    acpi_gas;
    uid:        uacpi_u32 #align 1;
    gpe_bit:    uacpi_u8;
//     ec_id:      *uacpi_char;// Incomplete array in C (zero-sized)
}

// acpi_dbg2_device_info->port_type
acpi_dbg2_type :: enum u32 {
    SERIAL :: 32768;
    _1394  :: 32769;
    USB    :: 32770;
    NET    :: 32771;
}

/*
* Constants for:
* - acpi_dbg2_device_info->port_subtype
*   if acpi_dbg2_device_info->port_type == ACPI_DBG2_TYPE_SERIAL.
* - acpi_spcr->interface_type (there is no type/subtype distinction in SPCR).
*/
acpi_dbg2_serial_subtype :: enum u32 {
    NS16550          :: 0;
    NS16550_DBGP1    :: 1;
    MAX311XE_SPI     :: 2;
    PL011            :: 3;
    MSM8X60          :: 4;
    NS16550_NVIDIA   :: 5;
    TI_OMAP          :: 6;
    APM88XXXX        :: 8;
    MSM8974          :: 9;
    SAM5250          :: 10;
    INTEL_USIF       :: 11;
    IMX6             :: 12;
    ARM_SBSA_32BIT   :: 13;
    ARM_SBSA_GENERIC :: 14;
    ARM_DCC          :: 15;
    BCM2835          :: 16;
    SDM845_1_8432MHZ :: 17;
    NS16550_GAS      :: 18;
    SDM845_7_372MHZ  :: 19;
    INTEL_LPSS       :: 20;
    RISCV_SBI        :: 21;
}

/*
* Constants for acpi_dbg2_device_info->port_subtype
* if acpi_dbg2_device_info->port_type == ACPI_DBG2_TYPE_1394.
*/
acpi_dbg2_1394_subtype :: enum u32 {
    ACPI_DBG2_SUBTYPE_1394_STANDARD :: 0;
}

/*
* Constants for acpi_dbg2_device_info->port_subtype
* if acpi_dbg2_device_info->port_type == ACPI_DBG2_TYPE_USB.
*/
acpi_dbg2_usb_subtype :: enum u32 {
    XHCI_DEBUG :: 0;
    EHCI_DEBUG :: 1;
}

acpi_dbg2 :: struct {
    hdr:                    acpi_sdt_hdr;
    offset_dbg_device_info: uacpi_u32 #align 1;
    number_dbg_device_info: uacpi_u32 #align 1;
}

acpi_dbg2_dbg_device_info :: struct {
    revision:                         uacpi_u8;
    length:                           uacpi_u16 #align 1;
    number_generic_address_registers: uacpi_u8;
    namespace_string_length:          uacpi_u16 #align 1;
    namespace_string_offset:          uacpi_u16 #align 1;
    oem_data_length:                  uacpi_u16 #align 1;
    oem_data_offset:                  uacpi_u16 #align 1;
    port_type:                        uacpi_u16 #align 1;
    port_subtype:                     uacpi_u16 #align 1;
    rsvd:                             uacpi_u16 #align 1;
    base_address_register_offset:     uacpi_u16 #align 1;
    address_size_offset:              uacpi_u16 #align 1;
}

// acpi_spcr->terminal_type
acpi_spcr_terminal_type :: enum u32 {
    VT100          :: 0;
    EXTENDED_VT100 :: 1;
    VT_UTF8        :: 2;
    ANSI           :: 3;
}

acpi_spcr :: struct {
    hdr:                     acpi_sdt_hdr;
    interface_type:          uacpi_u8;
    rsvd:                    [3] uacpi_u8;
    base_address:            acpi_gas;
    interrupt_type:          uacpi_u8;
    irq:                     uacpi_u8;
    gsi:                     uacpi_u32 #align 1;
    configured_baud_rate:    uacpi_u8;
    parity:                  uacpi_u8;
    stop_bits:               uacpi_u8;
    flow_control:            uacpi_u8;
    terminal_type:           uacpi_u8;
    language:                uacpi_u8;
    pci_device_id:           uacpi_u16 #align 1;
    pci_vendor_id:           uacpi_u16 #align 1;
    pci_bus_number:          uacpi_u8;
    pci_device_number:       uacpi_u8;
    pci_function_number:     uacpi_u8;
    pci_flags:               uacpi_u32 #align 1;
    pci_segment:             uacpi_u8;
    uart_clock_frequency:    uacpi_u32 #align 1;
    precise_baud_rate:       uacpi_u32 #align 1;
    namespace_string_length: uacpi_u16 #align 1;
    namespace_string_offset: uacpi_u16 #align 1;
}

acpi_rhct_hdr :: struct {
    type:     uacpi_u16 #align 1;
    length:   uacpi_u16 #align 1;
    revision: uacpi_u16 #align 1;
}

acpi_rhct :: struct {
    hdr:                acpi_sdt_hdr;
    flags:              uacpi_u32 #align 1;
    timebase_frequency: uacpi_u64 #align 1;
    node_count:         uacpi_u32 #align 1;
    nodes_offset:       uacpi_u32 #align 1;
//     entries:            *acpi_rhct_hdr;// Incomplete array in C (zero-sized)
}

acpi_rhct_entry_type :: enum u32 {
    ISA_STRING :: 0;
    CMO        :: 1;
    MMU        :: 2;
    HART_INFO  :: 65535;
}

acpi_rhct_isa_string :: struct {
    hdr:    acpi_rhct_hdr;
    length: uacpi_u16 #align 1;
//     isa:    *uacpi_u8;// Incomplete array in C (zero-sized)
}

acpi_rhct_cmo :: struct {
    hdr:       acpi_rhct_hdr;
    rsvd:      uacpi_u8;
    cbom_size: uacpi_u8;
    cbop_size: uacpi_u8;
    cboz_size: uacpi_u8;
}

acpi_rhct_mmu_type :: enum u32 {
    SV39 :: 0;
    SV48 :: 1;
    SV57 :: 2;
}

acpi_rhct_mmu :: struct {
    hdr:  acpi_rhct_hdr;
    rsvd: uacpi_u8;
    type: uacpi_u8;
}

acpi_rhct_hart_info :: struct {
    hdr:          acpi_rhct_hdr;
    offset_count: uacpi_u16 #align 1;
    uid:          uacpi_u32 #align 1;
//     offsets:      *uacpi_u32 #align 1;// Incomplete array in C (zero-sized)
}

/*
* Resources as encoded by the raw AML byte stream.
* For decode API & human usable structures refer to uacpi/resources.h
*/
acpi_small_item :: struct {
    type_and_length: uacpi_u8;
}

acpi_resource_irq :: struct {
    common:   acpi_small_item;
    irq_mask: uacpi_u16 #align 1;
    flags:    uacpi_u8;
}

acpi_resource_dma :: struct {
    common:       acpi_small_item;
    channel_mask: uacpi_u8;
    flags:        uacpi_u8;
}

acpi_resource_start_dependent :: struct {
    common: acpi_small_item;
    flags:  uacpi_u8;
}

acpi_resource_end_dependent :: struct {
    common: acpi_small_item;
}

acpi_resource_io :: struct {
    common:      acpi_small_item;
    information: uacpi_u8;
    minimum:     uacpi_u16 #align 1;
    maximum:     uacpi_u16 #align 1;
    alignment:   uacpi_u8;
    length:      uacpi_u8;
}

acpi_resource_fixed_io :: struct {
    common:  acpi_small_item;
    address: uacpi_u16 #align 1;
    length:  uacpi_u8;
}

acpi_resource_fixed_dma :: struct {
    common:         acpi_small_item;
    request_line:   uacpi_u16 #align 1;
    channel:        uacpi_u16 #align 1;
    transfer_width: uacpi_u8;
}

acpi_resource_vendor_defined_type0 :: struct {
    common:    acpi_small_item;
//     byte_data: *uacpi_u8;// Incomplete array in C (zero-sized)
}

acpi_resource_end_tag :: struct {
    common:   acpi_small_item;
    checksum: uacpi_u8;
}

acpi_large_item :: struct {
    type:   uacpi_u8;
    length: uacpi_u16 #align 1;
}

acpi_resource_memory24 :: struct {
    common:      acpi_large_item;
    information: uacpi_u8;
    minimum:     uacpi_u16 #align 1;
    maximum:     uacpi_u16 #align 1;
    alignment:   uacpi_u16 #align 1;
    length:      uacpi_u16 #align 1;
}

acpi_resource_vendor_defined_type1 :: struct {
    common:    acpi_large_item;
//     byte_data: *uacpi_u8;// Incomplete array in C (zero-sized)
}

acpi_resource_memory32 :: struct {
    common:      acpi_large_item;
    information: uacpi_u8;
    minimum:     uacpi_u32 #align 1;
    maximum:     uacpi_u32 #align 1;
    alignment:   uacpi_u32 #align 1;
    length:      uacpi_u32 #align 1;
}

acpi_resource_fixed_memory32 :: struct {
    common:      acpi_large_item;
    information: uacpi_u8;
    address:     uacpi_u32 #align 1;
    length:      uacpi_u32 #align 1;
}

acpi_resource_address :: struct {
    common:     acpi_large_item;
    type:       uacpi_u8;
    flags:      uacpi_u8;
    type_flags: uacpi_u8;
}

acpi_resource_address64 :: struct {
    common:             acpi_resource_address;
    granularity:        uacpi_u64 #align 1;
    minimum:            uacpi_u64 #align 1;
    maximum:            uacpi_u64 #align 1;
    translation_offset: uacpi_u64 #align 1;
    length:             uacpi_u64 #align 1;
}

acpi_resource_address32 :: struct {
    common:             acpi_resource_address;
    granularity:        uacpi_u32 #align 1;
    minimum:            uacpi_u32 #align 1;
    maximum:            uacpi_u32 #align 1;
    translation_offset: uacpi_u32 #align 1;
    length:             uacpi_u32 #align 1;
}

acpi_resource_address16 :: struct {
    common:             acpi_resource_address;
    granularity:        uacpi_u16 #align 1;
    minimum:            uacpi_u16 #align 1;
    maximum:            uacpi_u16 #align 1;
    translation_offset: uacpi_u16 #align 1;
    length:             uacpi_u16 #align 1;
}

acpi_resource_address64_extended :: struct {
    common:             acpi_resource_address;
    revision_id:        uacpi_u8;
    rsvd:               uacpi_u8;
    granularity:        uacpi_u64 #align 1;
    minimum:            uacpi_u64 #align 1;
    maximum:            uacpi_u64 #align 1;
    translation_offset: uacpi_u64 #align 1;
    length:             uacpi_u64 #align 1;
    attributes:         uacpi_u64 #align 1;
}

acpi_resource_extended_irq :: struct {
    common:   acpi_large_item;
    flags:    uacpi_u8;
    num_irqs: uacpi_u8;
//     irqs:     *uacpi_u32 #align 1;// Incomplete array in C (zero-sized)
}

acpi_resource_generic_register :: struct {
    common:           acpi_large_item;
    address_space_id: uacpi_u8;
    bit_width:        uacpi_u8;
    bit_offset:       uacpi_u8;
    access_size:      uacpi_u8;
    address:          uacpi_u64 #align 1;
}

acpi_resource_gpio_connection :: struct {
    common:             acpi_large_item;
    revision_id:        uacpi_u8;
    type:               uacpi_u8;
    general_flags:      uacpi_u16 #align 1;
    connection_flags:   uacpi_u16 #align 1;
    pull_configuration: uacpi_u8;
    drive_strength:     uacpi_u16 #align 1;
    debounce_timeout:   uacpi_u16 #align 1;
    pin_table_offset:   uacpi_u16 #align 1;
    source_index:       uacpi_u8;
    source_offset:      uacpi_u16 #align 1;
    vendor_data_offset: uacpi_u16 #align 1;
    vendor_data_length: uacpi_u16 #align 1;
}

acpi_resource_serial :: struct {
    common:                    acpi_large_item;
    revision_id:               uacpi_u8;
    source_index:              uacpi_u8;
    type:                      uacpi_u8;
    flags:                     uacpi_u8;
    type_specific_flags:       uacpi_u16 #align 1;
    type_specific_revision_id: uacpi_u8;
    type_data_length:          uacpi_u16 #align 1;
}

acpi_resource_serial_i2c :: struct {
    common:           acpi_resource_serial;
    connection_speed: uacpi_u32 #align 1;
    slave_address:    uacpi_u16 #align 1;
}

acpi_resource_serial_spi :: struct {
    common:           acpi_resource_serial;
    connection_speed: uacpi_u32 #align 1;
    data_bit_length:  uacpi_u8;
    phase:            uacpi_u8;
    polarity:         uacpi_u8;
    device_selection: uacpi_u16 #align 1;
}

acpi_resource_serial_uart :: struct {
    common:        acpi_resource_serial;
    baud_rate:     uacpi_u32 #align 1;
    rx_fifo:       uacpi_u16 #align 1;
    tx_fifo:       uacpi_u16 #align 1;
    parity:        uacpi_u8;
    lines_enabled: uacpi_u8;
}

acpi_resource_serial_csi2 :: struct {
    common: acpi_resource_serial;
}

acpi_resource_pin_function :: struct {
    common:             acpi_large_item;
    revision_id:        uacpi_u8;
    flags:              uacpi_u16 #align 1;
    pull_configuration: uacpi_u8;
    function_number:    uacpi_u16 #align 1;
    pin_table_offset:   uacpi_u16 #align 1;
    source_index:       uacpi_u8;
    source_offset:      uacpi_u16 #align 1;
    vendor_data_offset: uacpi_u16 #align 1;
    vendor_data_length: uacpi_u16 #align 1;
}

acpi_resource_pin_configuration :: struct {
    common:             acpi_large_item;
    revision_id:        uacpi_u8;
    flags:              uacpi_u16 #align 1;
    type:               uacpi_u8;
    value:              uacpi_u32 #align 1;
    pin_table_offset:   uacpi_u16 #align 1;
    source_index:       uacpi_u8;
    source_offset:      uacpi_u16 #align 1;
    vendor_data_offset: uacpi_u16 #align 1;
    vendor_data_length: uacpi_u16 #align 1;
}

acpi_resource_pin_group :: struct {
    common:              acpi_large_item;
    revision_id:         uacpi_u8;
    flags:               uacpi_u16 #align 1;
    pin_table_offset:    uacpi_u16 #align 1;
    source_lable_offset: uacpi_u16 #align 1;
    vendor_data_offset:  uacpi_u16 #align 1;
    vendor_data_length:  uacpi_u16 #align 1;
}

acpi_resource_pin_group_function :: struct {
    common:              acpi_large_item;
    revision_id:         uacpi_u8;
    flags:               uacpi_u16 #align 1;
    function:            uacpi_u16 #align 1;
    source_index:        uacpi_u8;
    source_offset:       uacpi_u16 #align 1;
    source_lable_offset: uacpi_u16 #align 1;
    vendor_data_offset:  uacpi_u16 #align 1;
    vendor_data_length:  uacpi_u16 #align 1;
}

acpi_resource_pin_group_configuration :: struct {
    common:              acpi_large_item;
    revision_id:         uacpi_u8;
    flags:               uacpi_u16 #align 1;
    type:                uacpi_u8;
    value:               uacpi_u32 #align 1;
    source_index:        uacpi_u8;
    source_offset:       uacpi_u16 #align 1;
    source_lable_offset: uacpi_u16 #align 1;
    vendor_data_offset:  uacpi_u16 #align 1;
    vendor_data_length:  uacpi_u16 #align 1;
}

acpi_resource_clock_input :: struct {
    common:       acpi_large_item;
    revision_id:  uacpi_u8;
    flags:        uacpi_u16 #align 1;
    divisor:      uacpi_u16 #align 1;
    numerator:    uacpi_u32 #align 1;
    source_index: uacpi_u8;
}

uacpi_fixed_event :: enum u32 {
    TIMER_STATUS :: 1;
    POWER_BUTTON :: 2;
    SLEEP_BUTTON :: 3;
    RTC          :: 4;
    MAX          :: 4;
}

uacpi_install_fixed_event_handler :: (event: uacpi_fixed_event, handler: uacpi_interrupt_handler, user: uacpi_handle) -> uacpi_status #foreign uacpi;

uacpi_uninstall_fixed_event_handler :: (event: uacpi_fixed_event) -> uacpi_status #foreign uacpi;

/*
* Enable/disable a fixed event. Note that the event is automatically enabled
* upon installing a handler to it.
*/
uacpi_enable_fixed_event :: (event: uacpi_fixed_event) -> uacpi_status #foreign uacpi;

/*
* Enable/disable a fixed event. Note that the event is automatically enabled
* upon installing a handler to it.
*/
uacpi_disable_fixed_event :: (event: uacpi_fixed_event) -> uacpi_status #foreign uacpi;

/*
* Enable/disable a fixed event. Note that the event is automatically enabled
* upon installing a handler to it.
*/
uacpi_clear_fixed_event :: (event: uacpi_fixed_event) -> uacpi_status #foreign uacpi;

/*
* Enable/disable a fixed event. Note that the event is automatically enabled
* upon installing a handler to it.
*/
uacpi_event_info :: enum u32 {
    ENABLED          :: 1;

    ENABLED_FOR_WAKE :: 2;

    MASKED           :: 4;

    HAS_HANDLER      :: 8;

    HW_ENABLED       :: 16;

    HW_STATUS        :: 32;
}

uacpi_fixed_event_info :: (event: uacpi_fixed_event, out_info: *uacpi_event_info) -> uacpi_status #foreign uacpi;

uacpi_gpe_info :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16, out_info: *uacpi_event_info) -> uacpi_status #foreign uacpi;

uacpi_gpe_handler :: #type (ctx: uacpi_handle, gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_interrupt_ret #c_call;

uacpi_gpe_triggering :: enum u32 {
    LEVEL :: 0;
    EDGE  :: 1;
    MAX   :: 1;
}

uacpi_gpe_triggering_to_string :: (triggering: uacpi_gpe_triggering) -> *uacpi_char #foreign uacpi;

/*
* Installs a handler to the provided GPE at 'idx' controlled by device
* 'gpe_device'. The GPE is automatically disabled & cleared according to the
* configured triggering upon invoking the handler. The event is optionally
* re-enabled (by returning UACPI_GPE_REENABLE from the handler)
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_install_gpe_handler :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16, triggering: uacpi_gpe_triggering, handler: uacpi_gpe_handler, ctx: uacpi_handle) -> uacpi_status #foreign uacpi;

/*
* Installs a raw handler to the provided GPE at 'idx' controlled by device
* 'gpe_device'. The handler is dispatched immediately after the event is
* received, status & enable bits are untouched.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_install_gpe_handler_raw :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16, triggering: uacpi_gpe_triggering, handler: uacpi_gpe_handler, ctx: uacpi_handle) -> uacpi_status #foreign uacpi;

/*
* Installs a raw handler to the provided GPE at 'idx' controlled by device
* 'gpe_device'. The handler is dispatched immediately after the event is
* received, status & enable bits are untouched.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_uninstall_gpe_handler :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16, handler: uacpi_gpe_handler) -> uacpi_status #foreign uacpi;

/*
* Marks the GPE 'idx' managed by 'gpe_device' as wake-capable. 'wake_device' is
* optional and configures the GPE to generate an implicit notification whenever
* an event occurs.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_setup_gpe_for_wake :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16, wake_device: *uacpi_namespace_node) -> uacpi_status #foreign uacpi;

/*
* Mark a GPE managed by 'gpe_device' as enabled/disabled for wake. The GPE must
* have previously been marked by calling uacpi_gpe_setup_for_wake. This
* function only affects the GPE enable register state following the call to
* uacpi_gpe_enable_all_for_wake.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_enable_gpe_for_wake :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Mark a GPE managed by 'gpe_device' as enabled/disabled for wake. The GPE must
* have previously been marked by calling uacpi_gpe_setup_for_wake. This
* function only affects the GPE enable register state following the call to
* uacpi_gpe_enable_all_for_wake.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_disable_gpe_for_wake :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Finalize GPE initialization by enabling all GPEs not configured for wake and
* having a matching AML handler detected.
*
* This should be called after the kernel power managment subsystem has
* enumerated all of the devices, executing their _PRW methods etc., and
* marking those it wishes to use for wake by calling uacpi_setup_gpe_for_wake
* or uacpi_mark_gpe_for_wake.
*/
uacpi_finalize_gpe_initialization :: () -> uacpi_status #foreign uacpi;

/*
* Enable/disable a general purpose event managed by 'gpe_device'. Internally
* this uses reference counting to make sure a GPE is not disabled until all
* possible users of it do so. GPEs not marked for wake are enabled
* automatically so this API is only needed for wake events or those that don't
* have a corresponding AML handler.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_enable_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Enable/disable a general purpose event managed by 'gpe_device'. Internally
* this uses reference counting to make sure a GPE is not disabled until all
* possible users of it do so. GPEs not marked for wake are enabled
* automatically so this API is only needed for wake events or those that don't
* have a corresponding AML handler.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_disable_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Clear the status bit of the event 'idx' managed by 'gpe_device'.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_clear_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Suspend/resume a general purpose event managed by 'gpe_device'. This bypasses
* the reference counting mechanism and unconditionally clears/sets the
* corresponding bit in the enable registers. This is used for switching the GPE
* to poll mode.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_suspend_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Suspend/resume a general purpose event managed by 'gpe_device'. This bypasses
* the reference counting mechanism and unconditionally clears/sets the
* corresponding bit in the enable registers. This is used for switching the GPE
* to poll mode.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_resume_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Finish handling the GPE managed by 'gpe_device' at 'idx'. This clears the
* status registers if it hasn't been cleared yet and re-enables the event if
* it was enabled before.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_finish_handling_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Hard mask/umask a general purpose event at 'idx' managed by 'gpe_device'.
* This is used to permanently silence an event so that further calls to
* enable/disable as well as suspend/resume get ignored. This might be necessary
* for GPEs that cause an event storm due to the kernel's inability to properly
* handle them. The only way to enable a masked event is by a call to unmask.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_mask_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Hard mask/umask a general purpose event at 'idx' managed by 'gpe_device'.
* This is used to permanently silence an event so that further calls to
* enable/disable as well as suspend/resume get ignored. This might be necessary
* for GPEs that cause an event storm due to the kernel's inability to properly
* handle them. The only way to enable a masked event is by a call to unmask.
*
* NOTE: 'gpe_device' may be null for GPEs managed by \_GPE
*/
uacpi_unmask_gpe :: (gpe_device: *uacpi_namespace_node, idx: uacpi_u16) -> uacpi_status #foreign uacpi;

/*
* Disable all GPEs currently set up on the system.
*/
uacpi_disable_all_gpes :: () -> uacpi_status #foreign uacpi;

/*
* Enable all GPEs not marked as wake. This is only needed after the system
* wakes from a shallow sleep state and is called automatically by wake code.
*/
uacpi_enable_all_runtime_gpes :: () -> uacpi_status #foreign uacpi;

/*
* Enable all GPEs marked as wake. This is only needed before the system goes
* to sleep is called automatically by sleep code.
*/
uacpi_enable_all_wake_gpes :: () -> uacpi_status #foreign uacpi;

/*
* Install/uninstall a new GPE block, usually defined by a device in the
* namespace with a _HID of ACPI0006.
*/
uacpi_install_gpe_block :: (gpe_device: *uacpi_namespace_node, address: uacpi_u64, address_space: uacpi_address_space, num_registers: uacpi_u16, irq: uacpi_u32) -> uacpi_status #foreign uacpi;

/*
* Install/uninstall a new GPE block, usually defined by a device in the
* namespace with a _HID of ACPI0006.
*/
uacpi_uninstall_gpe_block :: (gpe_device: *uacpi_namespace_node) -> uacpi_status #foreign uacpi;

uacpi_gas_read :: (gas: *acpi_gas, value: *uacpi_u64) -> uacpi_status #foreign uacpi;
uacpi_gas_write :: (gas: *acpi_gas, value: uacpi_u64) -> uacpi_status #foreign uacpi;

uacpi_mapped_gas :: struct {}

/*
* Map a GAS for faster access in the future. The handle returned via
* 'out_mapped' must be freed & unmapped using uacpi_unmap_gas() when
* no longer needed.
*/
uacpi_map_gas :: (gas: *acpi_gas, out_mapped: **uacpi_mapped_gas) -> uacpi_status #foreign uacpi;
uacpi_unmap_gas :: (unknown0: *uacpi_mapped_gas) -> void #foreign uacpi;

/*
* Same as uacpi_gas_{read,write} but operates on a pre-mapped handle for faster
* access and/or ability to use in critical sections/irq contexts.
*/
uacpi_gas_read_mapped :: (gas: *uacpi_mapped_gas, value: *uacpi_u64) -> uacpi_status #foreign uacpi;
uacpi_gas_write_mapped :: (gas: *uacpi_mapped_gas, value: uacpi_u64) -> uacpi_status #foreign uacpi;

uacpi_vendor_interface :: enum u32 {
    NONE                    :: 0;
    WINDOWS_2000            :: 1;
    WINDOWS_XP              :: 2;
    WINDOWS_XP_SP1          :: 3;
    WINDOWS_SERVER_2003     :: 4;
    WINDOWS_XP_SP2          :: 5;
    WINDOWS_SERVER_2003_SP1 :: 6;
    WINDOWS_VISTA           :: 7;
    WINDOWS_SERVER_2008     :: 8;
    WINDOWS_VISTA_SP1       :: 9;
    WINDOWS_VISTA_SP2       :: 10;
    WINDOWS_7               :: 11;
    WINDOWS_8               :: 12;
    WINDOWS_8_1             :: 13;
    WINDOWS_10              :: 14;
    WINDOWS_10_RS1          :: 15;
    WINDOWS_10_RS2          :: 16;
    WINDOWS_10_RS3          :: 17;
    WINDOWS_10_RS4          :: 18;
    WINDOWS_10_RS5          :: 19;
    WINDOWS_10_19H1         :: 20;
    WINDOWS_10_20H1         :: 21;
    WINDOWS_11              :: 22;
    WINDOWS_11_22H2         :: 23;
}

/*
* Returns the "latest" AML-queried _OSI vendor interface.
*
* E.g. for the following AML code:
*     _OSI("Windows 2021")
*     _OSI("Windows 2000")
*
* This function will return UACPI_VENDOR_INTERFACE_WINDOWS_11, since this is
* the latest version of the interface the code queried, even though the
* "Windows 2000" query came after "Windows 2021".
*/
uacpi_latest_queried_vendor_interface :: () -> uacpi_vendor_interface #foreign uacpi;

uacpi_interface_kind :: enum u32 {
    VENDOR  :: 1;
    FEATURE :: 2;
    ALL     :: 3;
}

/*
* Install or uninstall an interface.
*
* The interface kind is used for matching during interface enumeration in
* uacpi_bulk_configure_interfaces().
*
* After installing an interface, all _OSI queries report it as supported.
*/
uacpi_install_interface :: (name: *uacpi_char, unknown0: uacpi_interface_kind) -> uacpi_status #foreign uacpi;

uacpi_uninstall_interface :: (name: *uacpi_char) -> uacpi_status #foreign uacpi;

uacpi_host_interface :: enum u32 {
    MODULE_DEVICE               :: 1;
    PROCESSOR_DEVICE            :: 2;
    _3_0_THERMAL_MODEL          :: 3;
    _3_0_SCP_EXTENSIONS         :: 4;
    PROCESSOR_AGGREGATOR_DEVICE :: 5;
}

/*
* Same as install/uninstall interface, but comes with an enum of known
* interfaces defined by the ACPI specification. These are disabled by default
* as they depend on the host kernel support.
*/
uacpi_enable_host_interface :: (unknown0: uacpi_host_interface) -> uacpi_status #foreign uacpi;
uacpi_disable_host_interface :: (unknown0: uacpi_host_interface) -> uacpi_status #foreign uacpi;

uacpi_interface_handler :: #type (name: *uacpi_char, supported: uacpi_bool) -> uacpi_bool #c_call;

/*
* Set a custom interface query (_OSI) handler.
*
* This callback will be invoked for each _OSI query with the value
* passed in the _OSI, as well as whether the interface was detected as
* supported. The callback is able to override the return value dynamically
* or leave it untouched if desired (e.g. if it simply wants to log something or
* do internal bookkeeping of some kind).
*/
uacpi_set_interface_query_handler :: (unknown0: uacpi_interface_handler) -> uacpi_status #foreign uacpi;

uacpi_interface_action :: enum u32 {
    DISABLE :: 0;
    ENABLE  :: 1;
}

/*
* Bulk interface configuration, used to disable or enable all interfaces that
* match 'kind'.
*
* This is generally only needed to work around buggy hardware, for example if
* requested from the kernel command line.
*
* By default, all vendor strings (like "Windows 2000") are enabled, and all
* host features (like "3.0 Thermal Model") are disabled.
*/
uacpi_bulk_configure_interfaces :: (action: uacpi_interface_action, kind: uacpi_interface_kind) -> uacpi_status #foreign uacpi;

/*
* Set the firmware waking vector in FACS.
*
* 'addr32' is the real mode entry-point address
* 'addr64' is the protected mode entry-point address
*/
uacpi_set_waking_vector :: (addr32: uacpi_phys_addr, addr64: uacpi_phys_addr) -> uacpi_status #foreign uacpi;

/*
* Set the firmware waking vector in FACS.
*
* 'addr32' is the real mode entry-point address
* 'addr64' is the protected mode entry-point address
*/
uacpi_sleep_state :: enum u32 {
    S0  :: 0;
    S1  :: 1;
    S2  :: 2;
    S3  :: 3;
    S4  :: 4;
    S5  :: 5;
    MAX :: 5;
}

/*
* Prepare for a given sleep state.
* Must be caled with interrupts ENABLED.
*/
uacpi_prepare_for_sleep_state :: (unknown0: uacpi_sleep_state) -> uacpi_status #foreign uacpi;

/*
* Enter the given sleep state after preparation.
* Must be called with interrupts DISABLED.
*/
uacpi_enter_sleep_state :: (unknown0: uacpi_sleep_state) -> uacpi_status #foreign uacpi;

/*
* Prepare to leave the given sleep state.
* Must be called with interrupts DISABLED.
*/
uacpi_prepare_for_wake_from_sleep_state :: (unknown0: uacpi_sleep_state) -> uacpi_status #foreign uacpi;

/*
* Wake from the given sleep state.
* Must be called with interrupts ENABLED.
*/
uacpi_wake_from_sleep_state :: (unknown0: uacpi_sleep_state) -> uacpi_status #foreign uacpi;

/*
* Attempt reset via the FADT reset register.
*/
uacpi_reboot :: () -> uacpi_status #foreign uacpi;

#scope_file

uacpi :: #library,no_dll "./uacpi";
