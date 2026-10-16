open_hw
connect_hw_server
set targets [get_hw_targets]
puts "HW_TARGETS=$targets"
if {[llength $targets] > 0} {
    set t [lindex $targets 0]
    open_hw_target $t
    puts "OPEN_TARGET=$t"
    # 多次刷新尝试扫描 JTAG 链（FT232H 初始化 / 板上电需要时间）
    refresh_hw_server
    for {set i 0} {$i < 4} {incr i} {
        refresh_hw_target [current_hw_target]
        set devs [get_hw_devices]
        puts "TRY$i DEVICES=$devs"
        if {[llength $devs] > 0} { break }
        after 800
    }
    foreach d [get_hw_devices] {
        puts "DEV: $d  IDCODE=[get_property IDCODE $d]  PART=[get_property PART $d]"
    }
}
