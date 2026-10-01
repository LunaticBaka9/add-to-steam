// 用 Dolphin 同一条代码路径（KFileItemActions）验证「添加到 Steam」服务菜单
// 是否真的被 KIO 发现。仅用于开发期自动验证，不参与安装。
//
// 注意：故意用 printf 而不是 qInfo()——Qt6 在非 tty 环境下会把日志送进 journald，
// 管道里就什么都看不到了。
//
// 编译/运行见同目录 probe-servicemenu.sh
#include <cstdio>

#include <QAction>
#include <QApplication>
#include <QUrl>

#include <KFileItem>
#include <KFileItemActions>
#include <KFileItemListProperties>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (argc < 2) {
        std::fprintf(stderr, "usage: probe-servicemenu <file> [file...]\n");
        return 2;
    }

    KFileItemList items;
    for (int i = 1; i < argc; ++i) {
        items << KFileItem(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[i])));
    }

    KFileItemActions actions;
    actions.setItemListProperties(KFileItemListProperties(items));

    const QList<QAction *> list = actions.createServiceMenuActions();
    std::printf("service menu actions: %d\n", int(list.size()));
    for (QAction *action : list) {
        std::printf("ACTION: %s\n", action->text().toUtf8().constData());
    }
    std::fflush(stdout);
    return 0;
}
