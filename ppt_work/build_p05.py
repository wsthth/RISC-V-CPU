# -*- coding: utf-8 -*-
# build_p05.py: 验证与结果页（性能演进 scatter + 验证矩阵表）
import sys

sys.path.insert(0, r"C:\Users\tianhan\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\.skills\ppt")
from scripts.gen_svg_charts import chart_slide
from scripts.svg_lib.atomize_svg_to_slide import publish_slide

DECK = "Ut9AsEXbUlQ1IJdBe4mcrnlFnUf"

page_xml = """<slide xmlns="https://www.larkoffice.com/sml/2.0"><style><fill><fillColor color="rgb(252,252,250)"/></fill></style><data>
  <line startX="60" startY="64" endX="900" endY="64"><border color="rgb(207,216,228)" width="1"/></line>
  <shape type="text" topLeftX="60" topLeftY="36" width="400" height="26"><content textType="caption" fontSize="11" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left" wrap="false"><p>04 · 验证与结果</p></content></shape>
  <shape type="text" topLeftX="60" topLeftY="84" width="840" height="48"><content textType="headline" fontSize="32" fontFamily="思源宋体" color="rgba(24,38,58,1)" textAlign="left" lineSpacing="multiple:1.2"><p>官方测试集与 CoreMark：功能与性能双闭环</p></content></shape>
  <shape type="text" topLeftX="60" topLeftY="500" width="840" height="24"><content textType="caption" fontSize="11" fontFamily="思源宋体" color="rgba(105,120,140,1)" textAlign="left"><p>数据来源：本项目 Vivado 2019.1 仿真 log · 时钟频率 100 MHz 折算 · 周期数为硬件周期计数器实测</p></content></shape>
</data></slide>"""

frag_scatter = chart_slide(
    "scatter", 40, 120, 470, 330,
    points=[{
        "name": "单次迭代周期",
        "points": [
            {"x": 1, "y": 1.522},
            {"x": 2, "y": 1.152},
            {"x": 3, "y": 1.153},
        ],
    }],
    x_title="优化版本",
    y_title="迭代周期 (10^6 cycles)",
    end_labels=True,
    palette="sci_bluegreen",
    source="本项目仿真 log：v0.10 / v0.15 / v0.15.2",
)

page_table = """<table topLeftX="532" topLeftY="150" width="368" height="330">
  <colgroup>
    <col width="120"/>
    <col width="96"/>
    <col width="152"/>
  </colgroup>
  <tr height="34">
    <td><fill><fillColor color="rgba(24,38,58,1)"/></fill><content textType="body" fontSize="13" bold="true" color="rgba(255,255,255,1)" textAlign="left"><p>验证项</p></content></td>
    <td><fill><fillColor color="rgba(24,38,58,1)"/></fill><content textType="body" fontSize="13" bold="true" color="rgba(255,255,255,1)" textAlign="left"><p>结果</p></content></td>
    <td><fill><fillColor color="rgba(24,38,58,1)"/></fill><content textType="body" fontSize="13" bold="true" color="rgba(255,255,255,1)" textAlign="left"><p>说明</p></content></td>
  </tr>
  <tr height="52">
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>riscv-tests</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(81,157,120,1)" textAlign="left"><p>40/42</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>2 项 SKIP（fence.i / ma_data）有明确理由</p></content></td>
  </tr>
  <tr height="52">
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>CoreMark</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(81,157,120,1)" textAlign="left"><p>PASS</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>1,153,090 cycles，CRC 校验全对</p></content></td>
  </tr>
  <tr height="52">
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>matmul 3x3</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(81,157,120,1)" textAlign="left"><p>PASS</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>8,503 cycles，结果校验正确</p></content></td>
  </tr>
  <tr height="52">
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>qsort 8 元素</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(81,157,120,1)" textAlign="left"><p>PASS</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>871 cycles，排序结果校验正确</p></content></td>
  </tr>
  <tr height="52">
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>回归测试</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(81,157,120,1)" textAlign="left"><p>175/175</p></content></td>
    <td><content textType="body" fontSize="13" color="rgba(24,38,58,1)" textAlign="left"><p>每轮改动后全量回归</p></content></td>
  </tr>
</table>"""

if __name__ == "__main__":
    r = publish_slide(page_xml, frag_scatter, page_table, presentation=DECK, page=5)
    print(r["ok"], r["slide_id"])
    print("\n".join(r["summary"]))
