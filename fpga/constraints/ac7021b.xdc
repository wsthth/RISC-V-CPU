# ============================================================================
# AC7021B Լ���ļ���ALINX AC7021B / AX7021B ���İ壬xc7z020clg484-1��
# ----------------------------------------------------------------------------
# ����ȡ�� ALINX �ٷ��û��ֲᣨAX7021B_UG.pdf����
#   - PL ϵͳʱ�� 50MHz��Y9��BANK13 MRCC��LVCMOS33��
#   - �û� LED2��PL �ࣩ��R7���͵�ƽ������������ 3.3V��
#   - ��λ��PL ���޸�λ���������İ� RESET ���� PS_POR_B/B5��PL ���ڲ��ϵ縴λ��
# fpga_top ���� AC7021B �����䣨LED ����=1���͵�ƽ���������ⲿ��λ����
# ============================================================================

## ʱ�ӣ�50MHz
set_property PACKAGE_PIN Y9   [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name clk [get_ports clk]   # v0.15.3: 100MHz 收紧验证上板主频上限

## �û� LED2���͵�ƽ��������������˿�Ϊ���� led
set_property PACKAGE_PIN R7 [get_ports led]
set_property IOSTANDARD LVCMOS33 [get_ports led]
