# -*- coding: utf-8 -*-
import io

section = """

## 9. 答辩 PPT 制作（2026-10-20）

### 工作目标
- 完成赛题「答辩」评分项（15 分）中的 PPT 展示（5 分）：制作一份可直接答辩的演示文稿，
  覆盖赛题全部评分维度（设计文档、程序演示、性能论证、上板验证、团队协作）。

### 内容规划
- 选定设计系统：飞书 Slides「理工科院系答辩与正式学术报告」子风格，
  palette = `sci_bluegreen`（主题靛蓝 #5385BD / 辅助森绿 #519D78 / 深海蓝 #1E3C78 /
  背景象牙白 #FCFCFA / 标题深靛墨 #18263A / 正文蓝灰 #69788C），字体思源宋体，
  页面标题 32pt / 正文 16-17pt，页眉细线 + 章节编号。
- 页面规划（7 页）：
  1. 封面（标题 / 副题 / 占位元信息）；
  2. 项目背景与目标（设计指标 x 完成情况原生表格）；
  3. CPU 微架构（五级流水线手画示意图：IF/ID/EX/MEM/WB + 流水寄存器 + 分支预测器 +
     旁路转发 / Load-Use 停顿虚线）；
  4. 关键设计（冒险处理与分支预测表格：全旁路 / 2-bit+BTB / JAL 链接值 / 双重提交抑制）；
  5. 验证与结果（CoreMark 迭代周期随版本演进 scatter 图 + 验证矩阵表：riscv-tests 40/42、
     CoreMark PASS、matmul 8,503C、qsort 871C、回归 175/175）；
  6. 上板与性能（CoreMark 迭代/秒 grouped_bar：当前 90 / 单发射上限 128 / 赛题目标 250
     + 上板验证文字 + 250/s 数学不可达论证）；
  7. 总结与展望。

### 遇到的问题与解决
- 第 3 页示意图 lint：文字溢出背景窄条（流水寄存器 20px 宽放不下标签）+ 连线标签压框。
  - 解决：去掉流水寄存器窄条背景改为文字+短引线；移除 branch_resolved / MEM 旁路 / WB 旁路
    三个连线 label（信息保留在图例行）；pred 箭头 label 与 IF/ID 标签互压，一并移除。
  - 修复后文字类错误清零；剩余 7 条 bbox_overlap 均为箭头端点与阶段框接触的几何误报
    （publish_slide 自动豁免类别，截图确认无真实视觉问题，不回改）。
- PowerShell 重定向 `>` 写响应文件产生 UTF-16 BOM，python json.load 报 BOM 错误：
  - 解决：按 BOM 自动检测编码（utf-8-sig / utf-16 / utf-8）后再解析。
- lark-cli add-slide 偶发 stdout 为空（exit 0）：以 xml-get 回读为准确认写入状态，
  不回看命令行输出。

### 实验结果
- 7 页全部通过服务端 lint（第 3 页修复后文字错误清零）；
- xml_inspect 回读：slide_count=7，页序与规划一致；
- 逐页截图复核：封面、指标表、流水线示意图、关键设计表、scatter+验证矩阵、
  柱状图+论证、总结页全部渲染正常；
- 导出 PPTX（82.5 KB）：`ppt_work/基于RISC-V的高性能CPU设计与FPGA验证_答辩.pptx`；
- 在线 Slides：https://my.feishu.cn/slides/Ut9AsEXbUlQ1IJdBe4mcrnlFnUf

### 结论
- 答辩 PPT 展示项完成：一份可编辑在线版 + 一份本地 pptx，覆盖赛题全部评分维度。

### 下一步
1. （可选项）按现场要求替换封面占位（参赛团队 / 所属单位）；
2. CoreMark 上板 UART 输出演示（若现场需要）；
3. 演示视频（任务 #16，若赛题要求）；
4. 持续跟踪 AC7021B 100MHz 约束综合结果（build_ac7021b_v15c.log）。
"""

with io.open(r'D:\my_project\RISC-V\risc-v.md', 'a', encoding='utf-8', newline='\n') as f:
    f.write(section)
print('appended ok')
