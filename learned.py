import os

def merge_txt():
    zika_path = 'zika.txt'
    learned_path = 'learned.txt'

    # 1. 读取 zika.txt 中的单字
    if not os.path.exists(zika_path):
        print(f"未找到 {zika_path}，跳过处理。")
        return
        
    with open(zika_path, 'r', encoding='utf-8') as f:
        zika_words = f.read().split()

    if not zika_words:
        print("zika.txt 为空，无需合并。")
        return

    # 2. 读取 learned.txt 中的单字
    learned_words = []
    if os.path.exists(learned_path):
        with open(learned_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            # 如果文件不为空，且第一行包含“已学”，则从第二行开始读取单词
            if lines:
                if "已学" in lines[0]:
                    # 合并第二行及之后的所有文本并切分单词
                    content = " ".join(lines[1:])
                    learned_words = content.split()
                else:
                    # 如果原本没有标题行，则整篇读取
                    content = " ".join(lines)
                    learned_words = content.split()

    # 3. 使用集合（Set）去重并保持原有顺序
    learned_set = set(learned_words)
    new_words = [word for word in zika_words if word not in learned_set]

    if not new_words:
        print("没有发现新的未学习单字。")
        # 即使没有新词，我们也更新一下第一行的字数（防止原本字数统计不对）
        total_count = len(learned_words)
    else:
        # 合并新词
        learned_words.extend(new_words)
        total_count = len(learned_words)
        print(f"成功将 {len(new_words)} 个新字合并。")

    # 4. 写回 learned.txt
    # 第一行是字数统计，第二行是空格隔开的单字
    with open(learned_path, 'w', encoding='utf-8') as f:
        f.write(f"已学{total_count}字\n")
        f.write(' '.join(learned_words))
    
    print(f"当前总字数：{total_count}")

if __name__ == '__main__':
    merge_txt()
