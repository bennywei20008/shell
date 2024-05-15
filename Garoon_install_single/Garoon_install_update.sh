#!/bin/bash

# 定义Server/目录/密码等信息
PackageServer="10.224.147.180"
DBName="cbgrn"
ProgramFilePath="/usr/local/cybozu"
CGIDirectlyPath="/var/www/cgi-bin"
DocumentDirectlyPath="/var/www/html"
Password="cybozu"
Httpd="apache"

# 定义本地目录
LOCAL_WORK_DIR=$(
    cd $(dirname ${0})
    pwd
)

# 定义安装手顺命令文件
OUTPUT_FILE="operate_temp.txt"

# 连接archive server下载需要的版本
scp_server() {
    local package=$1

    # 下载指定的安装包
    sshpass -p 'Cybozu_123' scp -r root@$PackageServer:$LOCAL_WORK_DIR/archive/$package $LOCAL_WORK_DIR/
}

# 给下载的文件权限
change_permission() {
    local major_version=$1
    local minor_version=$2
    cd $LOCAL_WORK_DIR/

    if [[ -f "grn-${major_version}.0-linux-x64.bin" ]]; then
        chmod 777 "grn-${major_version}.0-linux-x64.bin"
    fi
    if [[ -f "grn-${major_version}.0a-linux-x64.bin" ]]; then
        chmod 777 "grn-${major_version}.0a-linux-x64.bin"
    fi

    if [[ -f "grn-${major_version}-sp${minor_version}-linux.bin" ]]; then
        chmod 777 "grn-${major_version}-sp${minor_version}-linux.bin"
    fi
    if [[ -f "grn-${major_version}.${minor_version}-linux-x64.bin" ]]; then
        chmod 777 "grn-${major_version}.${minor_version}-linux-x64.bin"
    fi
}

#update时先比较下版本，输入相同版本情况下不更新
compareVersions() {
    local version1=(${1//./ })
    local version2=(${2//./ })
    local maxLength=${#version1[@]}
    if [ ${#version2[@]} -gt $maxLength ]; then
        maxLength=${#version2[@]}
    fi
    for ((i = 0; i < maxLength; i++)); do
        if [ "${version1[i]:-0}" -gt "${version2[i]:-0}" ]; then
            return 0
        elif [ "${version1[i]:-0}" -lt "${version2[i]:-0}" ]; then
            return 1
        fi
    done
    return 1
}

# 定义下载安装函数
downloadGaroon() {
    local version=$1
    local major_version="${version%.*}"
    local minor_version="${version##*.}"
    local base_version="${major_version}.0"
    local base_package="grn-${base_version}-linux-x64.bin"
    local patch_package=""

    # 特殊处理5.15版本的base_package命名规则
    if [[ $major_version == "5.15" ]]; then
        base_package="grn-${base_version}a-linux-x64.bin"
    else
        base_package="grn-${base_version}-linux-x64.bin"
    fi

    # 判断是否为支持的主版本
    case $major_version in
    4.0 | 4.6 | 4.10 | 5.0 | 5.5 | 5.9 | 5.15 | 6.0)
        # 下载基础版本包
        scp_server "$base_package"

        # 判断sp子版本，如果有的则下载sp安装包
        if [[ $minor_version != "0" ]]; then
            # 特殊处理6.0版本的sp文件命名规则
            if [[ $major_version == "6.0" ]]; then
                patch_package="grn-${major_version}.${minor_version}-linux-x64.bin"
            else
                patch_package="grn-${major_version}-sp${minor_version}-linux.bin"
            fi
            scp_server "$patch_package"
        fi
        # 给下载的文件追加777权限
        change_permission $major_version $minor_version
        ;;
    *)
        echo "Unsupported version: $version"
        ;;
    esac
}

# 定义安装GaroonBase的函数
installGaroonBase() {
    local packageFile=$1
    # 使用expect脚本自动化交互过程
    expect <<EOF
    # 设置超时时间
    set timeout 60

    # 启动安装程序
    spawn sh $LOCAL_WORK_DIR/$packageFile

    # 初始化密码输入次数的计数器
    set passwordCount 0

    # 定义一个用于发送密码的过程
    proc sendPassword {} {
        global passwordCount Password
        if { \$passwordCount < 3 } {
            send "$Password\r"
            incr passwordCount
        }
    }

    # 根据提示自动输入响应
    expect {
        "*ガルーンのインストールを開始します。このメッセージが正しく表示されている場合はYを入力します。*" { send "Y\r"; exp_continue }
        "*インストールの準備をしています。しばらくお待ちください。*" { sleep 120; exp_continue }
        "*--続きます--*" { send "q"; exp_continue  }
        -re {\[yes or no\]:} { send "yes\r"; exp_continue }
        -re {\[cbgrn\]:} { send "$DBName\r"; exp_continue }
        -re {\[1|2\]:} { send "1\r"; exp_continue }
        -re {\[/usr/local/cybozu\]:} { send "$ProgramFilePath\r"; exp_continue }
        "Enter Password:" { sendPassword; exp_continue }
        -re {\[/var/www/cgi-bin\]:} { send "$CGIDirectlyPath\r"; exp_continue }
        -re {\[/var/www/html\]:} { send "$DocumentDirectlyPath\r"; exp_continue }
        -re {\[(apache|nobody)\]:} { send "$Httpd\r"; exp_continue }
        "*ガルーンにインストールするデータを選択してください。*" { send "1\r"; exp_continue  }
        "*上記の設定でインストールします。よろしいですか*" { send "yes\r"; exp_continue  }
    }
EOF
}

# 定义安装GaroonSP的函数
installAboveGaroon6SP() {
    local patchFile=$1
    # 使用expect脚本自动化交互过程
    expect <<EOF
# 设置超时时间
set timeout 60

# 启动安装程序
spawn sh $LOCAL_WORK_DIR/$patchFile

# 根据提示自动输入响应
expect {
    "*ガルーンのインストールを開始します。このメッセージが正しく表示されている場合はYを入力します。*" { send "Y\r"; exp_continue }
    "*インストールの準備をしています。しばらくお待ちください。*" { sleep 120; exp_continue }
    "*--続きます--*" { send "q"; exp_continue  }
    -re {\[yes or no\]:} { send "yes\r"; exp_continue }
    "*Garoonはすでにインストールされています。*" { send "1\r"; exp_continue }
    "Enter Password:" { send "$Password\r"; exp_continue }
     "*上記の設定でインストールします。よろしいですか*" { send "yes\r"; exp_continue  }
}
EOF
}

# 定义安装GaroonSP的函数
installBelowGaroon6SP() {
    local patchFile=$1
    # 使用expect脚本自动化交互过程
    expect <<EOF
# 设置超时时间
set timeout 60

# 启动安装程序
spawn sh $LOCAL_WORK_DIR/$patchFile

# 根据提示自动输入响应
expect {
    "*このメッセージが正しく表示されている場合はYを入力します。*" { send "Y\r"; exp_continue }
    "*インストールの準備をしています。しばらくお待ちください。*" { sleep 120; exp_continue }
    -re {\[yes or no\]:} { send "yes\r"; exp_continue }
    -re {\[id\]:} { send "$DBName\r"; exp_continue }
    "*上記の設定でインストールします。よろしいですか*" { send "yes\r"; exp_continue  }
}
EOF
}

updateGaroon() {
    local targetVersion=$1
    local installedVersion=$2
    local allVersions=("4.0" "4.0.1" "4.0.2" "4.0.3"
        "4.6.0" "4.6.1" "4.6.2" "4.6.3"
        "4.10.0" "4.10.1" "4.10.2" "4.10.3"
        "5.0.0" "5.0.1" "5.0.2"
        "5.5.0" "5.5.1"
        "5.9.0" "5.9.1" "5.9.2"
        "5.15.0" "5.15.1" "5.15.2"
        "6.0.0" "6.0.1" "6.0.2")
    local updateVersions=()
    local startUpdate=false

    for version in "${allVersions[@]}"; do
        if [[ "$version" == "$installedVersion" ]]; then
            startUpdate=true
        fi
        if $startUpdate && [[ "$version" > "$targetVersion" ]]; then
            break
        fi
        if $startUpdate && [[ "$version" != "$installedVersion" ]]; then
            updateVersions+=("$version")
        fi
    done

    local targetMajorVersion="${targetVersion%.*}"
    local targetMinorVersion="${targetVersion##*.}"
    local targetBaseVersion="${targetMajorVersion}.0"
    local targetBasePackage="grn-${targetBaseVersion}-linux-x64.bin"
    if [[ $targetMajorVersion == "5.15" ]]; then
        targetBasePackage="grn-${targetBaseVersion}a-linux-x64.bin"
    fi

    echo "downloading $targetVersion..."
    downloadGaroon $targetVersion
    installGaroonBase $targetBasePackage

    if [[ $targetMinorVersion != "0" ]]; then
        local targetPatchPackage=""
        if [[ $targetMajorVersion == "6.0" ]]; then
            targetPatchPackage="grn-${targetMajorVersion}.${targetMinorVersion}-linux-x64.bin"
            installAboveGaroon6SP $targetPatchPackage
        else
            targetPatchPackage="grn-${targetMajorVersion}-sp${targetMinorVersion}-linux.bin"
            installBelowGaroon6SP $targetPatchPackage
        fi
    fi
}

downloadArchive() {
    # 定义FileServer
    SERVER="//grbuild01.dev.cybozu.co.jp/Projects"
    USER="CRI%CRI"
    SHARE_PATH="CRI"

    major_version=$(echo $targetVersion | cut -d '.' -f 1)
    minor_version=$(echo $targetVersion | cut -d '.' -f 2)
    patch_version=$(echo $targetVersion | cut -d '.' -f 3)

    BASE_PATH=""

    # 确定packageversion版本
    if [[ $major_version -le "4" && $minor_version == "0" && $patch_version =~ [0-9] ]]; then
        # 3.0.0~4.0.9的版本
        packageversion="${major_version}"
        BASE_PATH="$SHARE_PATH/garoon$packageversion/$projectname/archive/"
        echo "BASE_PATH的路径是：" $BASE_PATH

    elif [[ $major_version == "5" && $minor_version == "0" && $patch_version =~ [0-9] ]]; then
        # 对于5.0.0~5.0.9的版本
        packageversion="${major_version}"
        BASE_PATH="$SHARE_PATH/garoon$packageversion/$projectname/archive/"
        echo "BASE_PATH的路径是：" $BASE_PATH

    elif [[ $major_version == "6" && $minor_version == "0" && $patch_version =~ [0-9] ]]; then
        # 6.0.0~6.0.9的版本
        packageversion="${major_version}.0"
        BASE_PATH="$SHARE_PATH/garoon_$packageversion.x/$projectname/archive/"
        echo "BASE_PATH的路径是：" $BASE_PATH

    elif [[ $major_version -eq "3" || $major_version -eq "4" || ($major_version -eq "5" && $minor_version -lt "5") ]]; then
        # 3.1.0~,4.1.0~,5.1.0~5.5之前的的版本
        packageversion="${major_version}${minor_version}"
        BASE_PATH="$SHARE_PATH/garoon$packageversion/$projectname/archive/"
        echo "BASE_PATH的路径是：" $BASE_PATH

    elif [[ $major_version -eq "5" && $minor_version -ge "5" ]] || [[ $major_version -eq "6" ]]; then
        # 对于5.5以上和6.1.0~以上的版本
        packageversion="${major_version}.${minor_version}"
        BASE_PATH="$SHARE_PATH/garoon_$packageversion.x/$projectname/archive/"
        echo "BASE_PATH的路径是：" $BASE_PATH

    else
        #其他版本情况不明，暂时先定义成和主版本一致的场合
        packageversion="${major_version}${minor_version}"
        BASE_PATH="$SHARE_PATH/garoon$packageversion/$projectname/archive/"
        echo "BASE_PATH的路径是：" $BASE_PATH
    fi

    # echo "BASE_PATH: $BASE_PATH"

    # 执行smbclient命令，列出目录内容
    OUTPUT=$(smbclient $SERVER -U $USER -c "cd \"$BASE_PATH\"; ls")

    # 使用awk处理输出，找到所有的目录，并按更新时间排序
    #LATEST_DIR=$(echo "$OUTPUT" | awk '/   D/{print $1 " " $3 " " $4 " " $5}' | grep -v '\.DS_Store' | sort -k2,4 | tail -1 | awk '{print $1}')
    LATEST_DIR=$(echo "$OUTPUT" | awk '/   D/{print $1}' | grep -v '\.DS_Store' | sort | tail -1)
    # echo "LATEST_DIR的路径是：" $LATEST_DIR

    if [ ! -z "$LATEST_DIR" ]; then
        LATEST_DIR_PATH="$BASE_PATH$LATEST_DIR"
        FILE_OUTPUT=$(smbclient $SERVER -U $USER -c "ls \"$LATEST_DIR_PATH/\"")
        echo "fileoutput:" $FILE_OUTPUT
        MATCHED_FILE=$(echo "$FILE_OUTPUT" | grep -oP "[^\s]+_ENC_\d{8}\.zip" | grep -v "patch" | head -n 1)
        # MATCHED_FILE=$(echo "$FILE_OUTPUT" | grep -oP "[^\s]+_ENC_\d{8}\.zip")
        echo "MATCHED_FILE:" $MATCHED_FILE
        MATCHED_OPERATE_FILE=$(echo "$FILE_OUTPUT" | grep -oP "readme_linux_normal.txt")
        echo "MATCHED_OPERATE_FILE:" $MATCHED_OPERATE_FILE
    fi

    if [ ! -z "$MATCHED_FILE" ]; then
        echo "Found file: $MATCHED_FILE"
        # 用smbclient去下载并拷贝文件
        smbclient $SERVER -U $USER -c "cd \"$LATEST_DIR_PATH\"; get \"$MATCHED_FILE\" \"$LOCAL_WORK_DIR/$MATCHED_FILE\""
        smbclient $SERVER -U $USER -c "cd \"$LATEST_DIR_PATH\"; get \"$MATCHED_OPERATE_FILE\" \"$LOCAL_WORK_DIR/$MATCHED_OPERATE_FILE\""
        echo "File $MATCHED_FILE has been copied to $LOCAL_WORK_DIR"
    else
        echo "No file matching pattern ($MATCHED_FILE) found in the latest directory."
    fi
    unzip -d $LOCAL_WORK_DIR $MATCHED_FILE
}

readmeextract() {
    local FILE_NAME="$1"

    awk -v start="コピーするファイルと対応するディレクトリー" -v end="コピーしたディレクトリーとファイルに、次のアクセス権があることを確認" '
        BEGIN { flag=0; print_content=0; prev="" }
        /ガルーンを運用しているサーバーマシンのWebサーバーを停止します。/,/スケジューリングサービスを停止します。/ {
            if (/\[root@garoon admin\]# /) { gsub(/\[root@garoon admin\]# /, ""); gsub(/^[ \t]+/, ""); print }
        }
        /スケジューリングサービスを停止します。/,/.*\.zipを解凍します。/ {
            if (/\[root@garoon admin\]# /) { gsub(/\[root@garoon admin\]# /, ""); gsub(/^[ \t]+/, ""); print }
        }
       /.*\.zipを解凍します。/,/ディレクトリーとファイルを、ガルーンがインストールされているディレクトリーに上書きコピーします。/ {
            if (/\[root@garoon admin\]# /) { gsub(/\[root@garoon admin\]# /, ""); gsub(/^[ \t]+/, ""); print }
        }
        $0 ~ start { flag=1; next }
        $0 ~ end { print_content=1; next }
        flag && !print_content && !/例\)/ && !/ex\)\\cp -fpr/ {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "");
            if (/=>/) {
                sub(/^[[:space:]]*=>[[:space:]]*/, "");
                gsub(/\[root@garoon admin\]# /, "");  # 替换命令提示符
                gsub(/^[ \t]+/, "");  # 去除行首空格
                print prev " " $0;
                prev="";
            } else {
                prev=$0;
            }
        }
        /キャッシュを削除します。/,EOF {
            if (/\/var\/www\/cgi-bin\/cbgrn\/smarty\/compiled/) { gsub(/\[root@garoon admin\]# /, ""); gsub(/^[ \t]+/, ""); print }
        }
    ' "$FILE_NAME"
}

# newfile=$MATCHED_FILE

# 从文件读取命令到数组
read_commands() {
    local i=0
    while IFS= read -r line; do
        commands[i]="$line"
        ((i++))
    done <"operate_temp.txt"
    # echo "read_commands:" $read_commands
    printf '%s\n' "${commands[@]}"
}

# 修改命令
modify_commands() {
    local modified_commands=()

    # 从operate_temp.txt中提取第一个.zip文件名
    MATCHED_FILE=$(grep -o '[^ ]*\.zip' operate_temp.txt | head -n 1)
    # echo "matchedfile:" $MATCHED_FILE

    if [[ -z "$MATCHED_FILE" ]]; then
        echo "No .zip file found in operate_temp.txt"
        return
    fi

    for cmd in "${commands[@]}"; do
        if [[ "$cmd" == "./source/"* ]]; then
            # 分割命令以获取源和目标路径
            IFS=' ' read -r -a parts <<<"$cmd"
            src="${parts[0]}"
            dest="${parts[1]}"
            modified_commands+=("\cp -fpr $src $dest")
        elif [[ "$cmd" == unzip* && "$cmd" == *.zip ]]; then
            # 替换包含unzip的命令行
            # modified_commands+=("unzip -d $LOCAL_WORK_DIR/$MATCHED_FILE")
            # modified_commands+=("unzip -d $LOCAL_WORK_DIR/$newfile")
            modified_commands+=("chmod 777 $LOCAL_WORK_DIR/source")
        elif [[ "$cmd" == "/var/www/cgi-bin/cbgrn/smarty/compiled" ]]; then
            modified_commands+=("rm -rf $cmd/*")
        else
            modified_commands+=("$cmd")
        fi
    done

    # 更新 commands 数组
    commands=("${modified_commands[@]}")
    # echo "Modified commands:"
    printf '%s\n' "${commands[@]}"
}

# 一条一条执行命令
run_commands() {
    echo "Executing commands:"
    for cmd in "${commands[@]}"; do
        echo "run command list check:" "$cmd"
        eval "$cmd"
    done
}

# 重启所有服务
restartservice() {
    # 重启Apache服务
    echo "Restarting Apache service..."
    sudo systemctl restart httpd.service
    echo "Apache service restarted."
    # # 重启GaroonDatabase服务
    # echo "Restarting GaroonDatabase service..."
    # sudo systemctl restart cyde_5_0.service
    # # sudo /etc/init.d/cyde_5_0.service restart
    # echo "GaroonDatabase service restarted."
    # # 重启GaroonSchedule服务
    # echo "Restarting GaroonSchedule service..."
    # sudo systemctl restart cyss_cbgrn.service
    # # sudo /etc/init.d/cyss_cbgrn.service restart
    # echo "GaroonSchedule service restarted."
}

# 删除已经安装的Garoon版本
uninstall() {
    unins=($(ls -r /usr/local | grep -E cybozu))

    if [ "${unins}" != "" ]; then
        echo "Start Uninstall Garoon..."
        $ProgramFilePath/mysql-5.0/uninstall_cyde_5_0 complete
        $CGIDirectlyPath/cbgrn/uninstall_cbgrn complete
        rm -rf $ProgramFilePath/
        rm -rf $CGIDirectlyPath/
    else
        echo "Garoon Uninstll is not installed in the environment."
    fi
}

# 提示用户输入操作和版本
read -p "What do you want to do? uninstall(1) or install(2) or update(3): " operate

case $operate in
uninstall | 1)
    uninstall
    ;;

install | 2)
    read -p "Which Garoon Version can you install: " targetVersion
    read -p "Do you want to install the customize customization package?(yes/no) " package

    version=$targetVersion
    major_version="${version%.*}"
    minor_version="${version##*.}"

    base_package="grn-${major_version}.0-linux-x64.bin"
    if [[ $major_version == "5.15" ]]; then
        base_package="grn-${major_version}.0a-linux-x64.bin"
    fi

    # 安装GaroonBase安装包
    function downloadAndInstallBasePackage {
        downloadGaroon $version
        installGaroonBase "$base_package"
    }

    # 如果有sp版本，判断后进行安装sp
    function installSP {
        if [[ $minor_version != "0" ]]; then
            case $major_version in
            "6.0")
                patch_package="grn-${major_version}.${minor_version}-linux-x64.bin"
                installAboveGaroon6SP "$patch_package"
                ;;
            "4.0" | "4.6" | "4.10" | "5.0" | "5.5" | "5.9" | "5.15")
                patch_package="grn-${major_version}-sp${minor_version}-linux.bin"
                installBelowGaroon6SP "$patch_package"
                ;;
            *)
                echo "Unsupported version for patching: $major_version"
                return 1
                ;;
            esac
        fi
    }

    # 根据用户选择执行相应的操作
    if [ "$package" = "yes" ]; then
        read -p "Enter the project name: " projectname
        downloadAndInstallBasePackage
        installSP
        restartservice
        downloadArchive
        readmeextract $LOCAL_WORK_DIR/$MATCHED_OPERATE_FILE >$LOCAL_WORK_DIR/$OUTPUT_FILE
        read_commands
        modify_commands
        run_commands
        restartservice
    elif [ "$package" = "no" ]; then
        downloadAndInstallBasePackage
        installSP
        restartservice
    else
        echo "Invalid package option: $package"
    fi
    ;;

update | 3)
    read -p "Which Garoon Version can you update to: " targetVersion
    read -p "Which Garoon version have you installed before?: " installedVersion
    read -p "Do you want to install the customize customization package?(yes/no) " package

    if [ "$package" = "yes" ]; then
        read -p "Enter the project name: " projectname
        if compareVersions "$targetVersion" "$installedVersion"; then
            echo "The updated version is greater than the current version. Start performing Garoon update and update the customizer package."
            downloadArchive
            readmeextract $LOCAL_WORK_DIR/$MATCHED_OPERATE_FILE >$LOCAL_WORK_DIR/$OUTPUT_FILE
            read_commands
            modify_commands
            updateGaroon $targetVersion $installedVersion
            run_commands
            restartservice
        elif [ "$targetVersion" = "$installedVersion" ]; then
            echo "The updated version is equal to the current version. There is no need to update Garoon. Start updating the customizer package."
            downloadArchive
            readmeextract $LOCAL_WORK_DIR/$MATCHED_OPERATE_FILE >$LOCAL_WORK_DIR/$OUTPUT_FILE
            read_commands
            modify_commands
            run_commands
            restartservice
        else
            echo "The updated version is smaller than the current version. There is no need to update Garoon. Start updating the customizer package."
        fi
        downloadArchive
        readmeextract $LOCAL_WORK_DIR/$MATCHED_OPERATE_FILE >$LOCAL_WORK_DIR/$OUTPUT_FILE
        read_commands
        modify_commands
        run_commands
        restartservice
    elif [ "$package" = "no" ]; then
        if compareVersions "$targetVersion" "$installedVersion"; then
            echo "The updated version is greater than the current version. Start performing Garoon update."
            updateGaroon $targetVersion $installedVersion
            restartservice
        elif [ "$targetVersion" = "$installedVersion" ]; then
            echo "The updated version is equal to the current version and there is no need to update Garoon."
        else
            echo "The updated version is smaller than the current version and there is no need to update Garoon."
        fi
    fi
    ;;
*)
    echo "Unsupported operation: $operate"
    ;;
esac
