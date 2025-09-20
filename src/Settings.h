#pragma once
#include <string>
#include <unordered_map>
#include <filesystem>
#include <optional>

/**
 * @file Settings.h
 * @brief 設定ファイルの読み書きを扱うユーティリティクラスの宣言。
 * @author 山内陽
 */

/**
 * @brief INI 形式の設定を読み込み・保存するクラス。
 */
class Settings {
public:
    /**
     * @brief 設定ファイルを読み込む。
     * @param path 対象ファイルパス。
     * @return 読み込みに成功した場合は true。
     */
    bool Load(const std::wstring& path);

    /**
     * @brief ファイルの更新を検知して再読み込みする。
     * @return 再読み込みを行った場合は true。
     */
    bool ReloadIfChanged();

    /**
     * @brief 現在の設定をファイルへ保存する。
     * @return 保存に成功した場合は true。
     */
    bool Save();

    /**
     * @brief 文字列値を取得する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @return 値が存在する場合は文字列、存在しなければ std::nullopt。
     */
    std::optional<std::string> GetString(const std::string& cat, const std::string& key) const;

    /**
     * @brief 倍精度浮動小数値を取得する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @param def 見つからない場合の既定値。
     * @return 取得した値、または既定値。
     */
    double GetDouble(const std::string& cat, const std::string& key, double def) const;

    /**
     * @brief 整数値を取得する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @param def 見つからない場合の既定値。
     * @return 取得した値、または既定値。
     */
    int    GetInt(const std::string& cat, const std::string& key, int def) const;

    /**
     * @brief 真偽値を取得する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @param def 見つからない場合の既定値。
     * @return 取得した値、または既定値。
     */
    bool   GetBool(const std::string& cat, const std::string& key, bool def) const;

    /**
     * @brief 文字列値を設定する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @param v 設定する値。
     */
    void   SetString(const std::string& cat, const std::string& key, const std::string& v);

    /**
     * @brief 倍精度浮動小数値を設定する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @param v 設定する値。
     */
    void   SetDouble(const std::string& cat, const std::string& key, double v);

    /**
     * @brief 整数値を設定する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @param v 設定する値。
     */
    void   SetInt(const std::string& cat, const std::string& key, int v);

    /**
     * @brief 真偽値を設定する。
     * @param cat カテゴリ名。
     * @param key キー名。
     * @param v 設定する値。
     */
    void   SetBool(const std::string& cat, const std::string& key, bool v);

    /**
     * @brief 現在参照しているパスを取得する。
     * @return 設定ファイルのパス。
     */
    std::wstring Path() const { return m_path; }

private:
    /**
     * @brief INI 形式文字列を解析して内部データに反映する。
     * @param text 解析するテキスト。
     * @return 解析に成功した場合は true。
     */
    bool Parse(const std::string& text);

    using KV = std::unordered_map<std::string, std::string>;
    std::unordered_map<std::string, KV> m_data;      // カテゴリ別のキー・値テーブル
    std::wstring m_path;                            // 設定ファイルのパス
    std::filesystem::file_time_type m_lastWriteTime{}; // 最終更新時刻
};
