package system

import (
	"errors"
	"log"
	"server/config"
	"server/plugin/db"

	"gorm.io/gorm"
)

// ErrUserNotFound 用户不存在
var ErrUserNotFound = errors.New("用户不存在")

// MigrateV1 启动时补齐多端客户端所需的表与字段
func MigrateV1() {
	if err := db.Mdb.AutoMigrate(&User{}, &UserFavorite{}, &UserWatchHistory{}); err != nil {
		log.Println("V1 AutoMigrate Failed: ", err)
	}
	// 用户名唯一索引, 防止并发注册产生重复账号
	if !db.Mdb.Migrator().HasIndex(&User{}, "idx_user_name") {
		if err := db.Mdb.Exec("CREATE UNIQUE INDEX idx_user_name ON users (user_name)").Error; err != nil {
			log.Println("Create UserName Unique Index Failed: ", err)
		}
	}
	// 历史数据角色字段补全
	db.Mdb.Model(&User{}).Where("role = ? OR role IS NULL OR role = ''", "").Update("role", config.RoleUser)
	db.Mdb.Model(&User{}).Where("user_name = ?", "admin").Update("role", config.RoleAdmin)
}

// FindUserByID 查询用户, 不存在时返回 ErrUserNotFound
func FindUserByID(id uint) (*User, error) {
	var u User
	if err := db.Mdb.First(&u, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}
	return &u, nil
}

// FindUserByNameOrEmail 通过用户名或邮箱查询用户
func FindUserByNameOrEmail(account string) (*User, error) {
	var u User
	if err := db.Mdb.Where("user_name = ? OR email = ?", account, account).First(&u).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}
	return &u, nil
}

// CreateUser 创建用户
func CreateUser(u *User) error {
	return db.Mdb.Create(u).Error
}

// UpdateUserPasswordHash 更新密码并清空历史盐值
func UpdateUserPasswordHash(id uint, hash string) error {
	return db.Mdb.Model(&User{}).Where("id = ?", id).Updates(map[string]interface{}{
		"password": hash,
		"salt":     "",
	}).Error
}

// IsAdmin 判断用户是否管理员
func IsAdmin(id uint) bool {
	u, err := FindUserByID(id)
	if err != nil {
		return false
	}
	return u.Role == config.RoleAdmin
}
