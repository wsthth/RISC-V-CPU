# -*- coding: utf-8 -*-
# build_p03.py: 五级流水线架构示意图
import sys

sys.path.insert(0, r"C:\Users\tianhan\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\.skills\ppt")
from scripts.svg_lib.svg_drawing import Drawing
from scripts.svg_lib.atomize_svg_to_slide import publish_slide

DECK = "Ut9AsEXbUlQ1IJdBe4mcrnlFnUf"

page_xml = """<slide xmlns="https://www.larkoffice.com/sml/2.0"><style><fill><fillColor color="rgb(252,252,250)"/></fill></style><data>
  <line startX="60" startY="64" endX="900" endY="64"><border color="rgb(207,216,228)" width="1"/></line>
  <shape type="text" topLeftX="60" topLeftY="36" width="400" height="26"><content textType="caption" fontSize="11" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left" wrap="false"><p>02 · CPU 微架构</p></content></shape>
  <shape type="text" topLeftX="60" topLeftY="84" width="840" height="48"><content textType="headline" fontSize="32" fontFamily="思源宋体" color="rgba(24,38,58,1)" textAlign="left" lineSpacing="multiple:1.2"><p>五级流水线：全旁路转发 + 分支预测 + BTB</p></content></shape>
  <shape type="text" topLeftX="60" topLeftY="500" width="840" height="24"><content textType="caption" fontSize="11" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left"><p>数据流（实线）与旁路 / 预测反馈（虚线）示意 · 仿真验证 175 cycles 回归全绿</p></content></shape>
</data></slide>"""

d = Drawing(900, 380)

# ---- 五级流水段（主行 y=210，框高 64）----
stage_defs = [
    ("IF 取指", "imem 读出指令\npc + 4", 40),
    ("ID 译码", "regfile 读\n立即数扩展", 230),
    ("EX 执行", "ALU 运算\n分支解析", 420),
    ("MEM 访存", "dmem 读写\nMMIO", 610),
    ("WB 写回", "regfile 写回", 800),
]
stage_nodes = []
for name, sub, x in stage_defs:
    b = d.box_at((x + 75, 210), name, font_size=17, fill="#EDF3FA", stroke="#5385BD",
                 text_fill="#18263A", shape="rect", max_width=138, height=30)
    stage_nodes.append(b)
    d.text_at((x + 75, 248), sub, font_size=11, fill="#69788C")

# ---- 流水寄存器（主行上方标注，无背景条避免文字溢出）----
reg_defs = [("IF/ID", 185), ("ID/EX", 375), ("EX/MEM", 565), ("MEM/WB", 755)]
reg_nodes = []
for name, cx in reg_defs:
    t = d.text_at((cx + 10, 146), name, font_size=9, fill="#788494")
    reg_nodes.append(t)
    d.line((cx + 10, 156), (cx + 10, 178), stroke="#788494", stroke_width=1)

# ---- 主数据流箭头（段间水平）----
for i in range(4):
    d.arrow(stage_nodes[i], stage_nodes[i + 1], head="arrow", stroke="#5385BD", stroke_width=2.2)

# ---- 分支预测器（顶部）----
pred = d.box_at((150, 70), "分支预测器\n2-bit 饱和计数 + BTB 128 项", font_size=13,
                fill="#E7F3EC", stroke="#519D78", text_fill="#18263A", shape="rect", max_width=210, height=44)
d.arrow(pred, stage_nodes[0], head="arrow", stroke="#519D78", stroke_width=2, route="orthogonal")
# EX 更新反馈（虚线，右侧绕回）
d.arrow(stage_nodes[2], pred, head="arrow", dashed=True, stroke="#A7B6A1", stroke_width=1.8,
        route="orthogonal", curve=-60)

# ---- 旁路转发（MEM -> EX, WB -> EX，下方虚线，无标签避免压框）----
d.arrow(stage_nodes[3], stage_nodes[2], head="arrow", dashed=True, stroke="#A7B6A1",
        stroke_width=1.8, route="elbow")
d.arrow(stage_nodes[4], stage_nodes[2], head="arrow", dashed=True, stroke="#A7B6A1",
        stroke_width=1.8, route="elbow", curve=40)

# ---- Load-Use 停顿（ID -> IF 虚线）----
d.arrow(stage_nodes[1], stage_nodes[0], head="arrow", dashed=True, stroke="#C9A227",
        stroke_width=1.6, route="orthogonal", curve=30)

# ---- 底部图例 ----
d.text_at((450, 336), "实线：指令流水主通路    虚线：旁路转发 / 分支预测反馈 / 停顿控制", font_size=12, fill="#788494")

if __name__ == "__main__":
    r = publish_slide(page_xml, d.to_slide(x=30, y=96, width=900), presentation=DECK, slide_id="pnC")
    print(r["ok"], r["slide_id"])
    print("\n".join(r["summary"]))
