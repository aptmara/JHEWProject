/**
 * @file Settings.cpp
 * @brief 設定ファイル読み書きクラスの実装。
 * @author 山内陽
 */

#include "Settings.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>

using namespace std;

/**
 * @brief 文字列の前後空白を取り除くヘルパー。
 * @param s 処理対象の文字列。
 */
static inline void trim(string& s)
{
    auto issp = [](int ch) { return std::isspace(ch); };
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), [&](char c) { return !issp((unsigned char)c); }));
    s.erase(std::find_if(s.rbegin(), s.rend(), [&](char c) { return !issp((unsigned char)c); }).base(), s.end());
}

/**
 * @brief 設定ファイルを読み込む。
 * @param path ファイルパス。
 * @return 読み込みに成功した場合は true。
 */
bool Settings::Load(const std::wstring& path)
{
    m_path = path;
    if (!std::filesystem::exists(path))
        return false;

    std::ifstream ifs(path);
    if (!ifs)
        return false;
    std::stringstream buf;
    buf << ifs.rdbuf();
    if (!Parse(buf.str()))
        return false;

    m_lastWriteTime = std::filesystem::last_write_time(path);
    return true;
}

/**
 * @brief ファイルの更新を監視し変化があれば再読み込みする。
 * @return 再読み込みを実施した場合は true。
 */
bool Settings::ReloadIfChanged()
{
    if (m_path.empty() || !std::filesystem::exists(m_path))
        return false;
    auto now = std::filesystem::last_write_time(m_path);
    if (now != m_lastWriteTime)
    {
        std::ifstream ifs(m_path);
        if (!ifs)
            return false;
        std::stringstream buf;
        buf << ifs.rdbuf();
        if (!Parse(buf.str()))
            return false;
        m_lastWriteTime = now;
        return true;
    }
    return false;
}

/**
 * @brief INI テキストを解析して内部辞書に展開する。
 * @param text 解析対象のテキスト。
 * @return 成功した場合は true。
 */
bool Settings::Parse(const std::string& text)
{
    m_data.clear();
    std::istringstream iss(text);
    std::string line;
    std::string currentCat = "Default";

    while (std::getline(iss, line))
    {
        auto semi = line.find(';');
        if (semi != std::string::npos)
            line.erase(semi);
        auto hash = line.find('#');
        if (hash != std::string::npos)
            line.erase(hash);

        trim(line);
        if (line.empty())
            continue;

        if (line.front() == '[' && line.back() == ']')
        {
            currentCat = line.substr(1, line.size() - 2);
            trim(currentCat);
            continue;
        }

        auto eq = line.find('=');
        if (eq == std::string::npos)
            continue;

        std::string key = line.substr(0, eq);
        std::string val = line.substr(eq + 1);
        trim(key);
        trim(val);
        m_data[currentCat][key] = val;
    }
    return true;
}

/**
 * @brief 文字列値を取得する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @return 値が存在すればその文字列、無ければ std::nullopt。
 */
std::optional<std::string> Settings::GetString(const std::string& cat, const std::string& key) const
{
    auto itc = m_data.find(cat);
    if (itc == m_data.end())
        return std::nullopt;
    auto itk = itc->second.find(key);
    if (itk == itc->second.end())
        return std::nullopt;
    return itk->second;
}

/**
 * @brief 倍精度浮動小数値を取得する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @param def 見つからない場合の既定値。
 * @return 値または既定値。
 */
double Settings::GetDouble(const std::string& cat, const std::string& key, double def) const
{
    auto s = GetString(cat, key);
    if (!s)
        return def;
    try
    {
        return std::stod(*s);
    }
    catch (...)
    {
        return def;
    }
}

/**
 * @brief 整数値を取得する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @param def 見つからない場合の既定値。
 * @return 値または既定値。
 */
int Settings::GetInt(const std::string& cat, const std::string& key, int def) const
{
    auto s = GetString(cat, key);
    if (!s)
        return def;
    try
    {
        return std::stoi(*s);
    }
    catch (...)
    {
        return def;
    }
}

/**
 * @brief 真偽値を取得する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @param def 見つからない場合の既定値。
 * @return 値または既定値。
 */
bool Settings::GetBool(const std::string& cat, const std::string& key, bool def) const
{
    auto s = GetString(cat, key);
    if (!s)
        return def;
    std::string v = *s;
    std::transform(v.begin(), v.end(), v.begin(), ::tolower);
    if (v == "1" || v == "true" || v == "on" || v == "yes")
        return true;
    if (v == "0" || v == "false" || v == "off" || v == "no")
        return false;
    return def;
}

/**
 * @brief 文字列値を設定する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @param v 設定する値。
 */
void Settings::SetString(const std::string& cat, const std::string& key, const std::string& v)
{
    m_data[cat][key] = v;
}
/**
 * @brief 倍精度浮動小数値を設定する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @param v 設定する値。
 */
void Settings::SetDouble(const std::string& cat, const std::string& key, double v)
{
    m_data[cat][key] = std::to_string(v);
}
/**
 * @brief 整数値を設定する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @param v 設定する値。
 */
void Settings::SetInt(const std::string& cat, const std::string& key, int v)
{
    m_data[cat][key] = std::to_string(v);
}
/**
 * @brief 真偽値を設定する。
 * @param cat カテゴリ名。
 * @param key キー名。
 * @param v 設定する値。
 */
void Settings::SetBool(const std::string& cat, const std::string& key, bool v)
{
    m_data[cat][key] = v ? "1" : "0";
}

/**
 * @brief 現在の設定内容をファイルへ書き出す。
 * @return 保存に成功した場合は true。
 */
bool Settings::Save()
{
    if (m_path.empty())
        return false;
    std::ofstream ofs(m_path, std::ios::trunc);
    if (!ofs)
        return false;

    for (auto& [cat, kv] : m_data)
    {
        ofs << "[" << cat << "]\n";
        for (auto& [k, v] : kv)
            ofs << k << "=" << v << "\n";
        ofs << "\n";
    }
    ofs.flush();
    ofs.close();

    if (std::filesystem::exists(m_path))
    {
        m_lastWriteTime = std::filesystem::last_write_time(m_path);
    }
    return true;
}
