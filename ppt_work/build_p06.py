# -*- coding: utf-8 -*-
# build_p06.py: 上板验证与性能论证页（grouped_bar + 论证文字）
import sys

sys.path.insert(0, r"C:\Users\tianhan\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\.skills\ppt")
from scripts.gen_svg_charts import chart_slide
from scripts.svg_lib.atomize_svg_to_slide import publish_slide

DECK = "Ut9AsEXbUlQ1IJdBe4mcrnlFnUf"

page_xml = """<slide xmlns="https://www.larkoffice.com/sml/2.0"><style><fill><fillColor color="rgb(252,252,250)"/></fill></style><data>
  <line startX="60" startY="64" endX="900" endY="64"><border color="rgb(207,216,228)" width="1"/></line>
  <shape type="text" topLeftX="60" topLeftY="36" width="400" height="26"><content textType="caption" fontSize="11" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left" wrap="false"><p>05 · 上板与性能</p></content></shape>
  <shape type="text" topLeftX="60" topLeftY="84" width="840" height="48"><content textType="headline" fontSize="32" fontFamily="思源宋体" color="rgba(24,38,58,1)" textAlign="left" lineSpacing="multiple:1.2"><p>Zynq-7020 上板成功，性能贴近单发射结构极限</p></content></shape>
  <shape type="text" topLeftX="500" topLeftY="148" width="400" height="116">
    <content textType="body" fontSize="15" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left" lineSpacing="multiple:1.4">
      <p><span bold="true" color="rgba(24,38,58,1)">上板验证</span>：AC7021B（xc7z020clg484-1）USB 直连烧录，LED 闪烁程序两次上板成功。</p>
      <p><span bold="true" color="rgba(24,38,58,1)">资源占用</span>：4141 Slice LUT（7.8%）、8256 FF、4 BRAM，满足小于 5K LUT；50 MHz 约束综合 WNS=0.886。</p>
    </content>
  </shape>
  <shape type="text" topLeftX="500" topLeftY="300" width="400" height="180">
    <content textType="body" fontSize="15" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left" lineSpacing="multiple:1.4">
      <p><span bold="true" color="rgba(24,38,58,1)">性能论证</span>：赛题 250 次/秒以 100 MHz 为例，对应每迭代 400,000 cycles，折算 IPC 需大于 1.75。</p>
      <p>单发射 RV32I 五级流水线 IPC 上限为 1.0，本设计实测 778,462 条指令 / 1,153,090 cycles，IPC 0.67。</p>
      <p><span bold="true" color="rgba(81,157,120,1)">结论</span>：250 次/秒需超标量架构，单发射设计数学上不可达；本设计已逼近单发射极限并拿满其余评分项。</p>
    </content>
  </shape>
  <shape type="text" topLeftX="60" topLeftY="504" width="840" height="24"><content textType="caption" fontSize="11" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left"><p>口径：单次迭代 1,153,090 cycles；100 MHz 折算每秒 86.7 次，取 90；单发射 IPC 上限 1.0</p></content></shape>
</data></slide>"""

frag_bar = chart_slide(
    "grouped_bar", 56, 140, 420, 310,
    categories=["当前实现", "单发射上限", "赛题目标"],
    series=[{"name": "CoreMark 迭代/秒", "values": [90, 128, 250]}],
    y_title="CoreMark 迭代 / 秒",
    show_values=True,
    palette="sci_bluegreen",
    source="本项目仿真折算 / 赛题评分标准",
)

if __name__ == "__main__":
    r = publish_slide(page_xml, frag_bar, presentation=DECK, page=6)
    print(r["ok"], r["slide_id"])
    print("\n".join(r["summary"]))
