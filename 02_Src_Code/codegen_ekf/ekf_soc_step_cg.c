/*
 * File: ekf_soc_step_cg.c
 *
 * MATLAB Coder version            : 25.1
 * C/C++ source code generated on  : 2026-06-05 15:20:07
 */

/* Include Files */
#include "ekf_soc_step_cg.h"
#include "ekf_soc_step_cg_data.h"
#include "ekf_soc_step_cg_initialize.h"
#include "ekf_soc_step_cg_types.h"
#include "eye.h"
#include <math.h>
#include <string.h>

/* Variable Definitions */
static bool x_not_empty;

/* Function Definitions */
/*
 * EKF_SOC_STEP_CG 单步 EKF SOC 估算（嵌入式单周期调用版，供 STM32 部署）
 *    [soc, vrc, vhat] = EKF_SOC_STEP_CG(I_k, V_k, dt, prm, reset)
 *    每个采样周期调用一次，内部用 persistent 保持状态 x=[SOC;Vrc] 与协方差 P，
 *    契合 MCU 实时循环。区别于批处理版 ekf_soc_estimator_cg：
 *      - 标量输入/输出，固定大小（OCV 查表 21
 * 点定长），无动态内存(emxArray/malloc)；
 *      - persistent 状态跨调用保持；reset=true 时按 prm.soc0 重新初始化。
 *    适合 Cortex-M4F/M7（带 FPU）直接集成；生成的 C
 * 为静态内存、可重入到单实例。
 *
 *    状态方程（放电 I>0）：SOC -= dt/(3600*Cap)*I；Vrc = a*Vrc + R1*(1-a)*I
 *    观测方程：V = OCV(SOC) - R0*I - Vrc；雅可比 C=[dOCV/dSOC, -1]
 *
 *    输入：
 *      I_k   - 当前电流 (A)，放电为正
 *      V_k   - 当前端电压观测 (V)
 *      dt    - 采样步长 (s)
 *      prm   - 参数结构体（字段全部必填，OCV_bp/SOC_bp 为 21x1 定长）：
 *                R0_Ohm,R1_Ohm,C1_F,Cap_Ah,SOC_bp(21),OCV_bp(21),soc0,Q(2x2),R,P0(2x2)
 *      reset - 逻辑标量，true 时用 prm.soc0/P0 重置状态（上电/重启时置 true）
 *    输出：
 *      soc   - 当前 SOC 估计 [0,1]；vrc - 极化电压；vhat - 预测端电压
 *
 *    参考：Plett, "Battery Management Systems, Vol.2", Ch.3 EKF。
 *
 * Arguments    : double I_k
 *                double V_k
 *                double dt
 *                const struct0_T *prm
 *                bool reset
 *                double *soc
 *                double *vrc
 *                double *vhat
 * Return Type  : void
 */
void ekf_soc_step_cg(double I_k, double V_k, double dt, const struct0_T *prm,
                     bool reset, double *soc, double *vrc, double *vhat)
{
  static double P[4];
  static double x[2];
  double A[4];
  double b_A[4];
  double Cmat[2];
  double K_idx_0;
  double S;
  double a;
  double b;
  double dOCV;
  double xq;
  int b_i;
  int k;
  if (!isInitialized_ekf_soc_step_cg) {
    ekf_soc_step_cg_initialize();
  }
  if ((!x_not_empty) || reset) {
    x[0] = prm->soc0;
    x[1] = 0.0;
    x_not_empty = true;
    P[0] = prm->P0[0];
    P[1] = prm->P0[1];
    P[2] = prm->P0[2];
    P[3] = prm->P0[3];
  }
  a = exp(-dt / (prm->R1_Ohm * prm->C1_F));
  /*  --- 观测预测（linear 查表 + 线段斜率）--- */
  xq = x[0];
  /* LUT_LINEAR21 21 点一维线性查表 + 线段斜率（定长，codegen 嵌入式友好） */
  /*  ===== 局部函数 ===== */
  if (x[0] <= prm->SOC_bp[0]) {
    k = 0;
  } else if (x[0] >= prm->SOC_bp[20]) {
    k = 19;
  } else {
    int i;
    bool exitg1;
    k = 0;
    i = 0;
    exitg1 = false;
    while ((!exitg1) && (i < 20)) {
      if ((xq >= prm->SOC_bp[i]) && (xq <= prm->SOC_bp[i + 1])) {
        k = i;
        exitg1 = true;
      } else {
        i++;
      }
    }
  }
  dOCV = (prm->OCV_bp[k + 1] - prm->OCV_bp[k]) /
         (prm->SOC_bp[k + 1] - prm->SOC_bp[k]);
  *vhat =
      ((prm->OCV_bp[k] + dOCV * (x[0] - prm->SOC_bp[k])) - prm->R0_Ohm * I_k) -
      x[1];
  /*  --- 量测更新 --- */
  memset(&Cmat[0], 0, sizeof(double) << 1);
  xq = dOCV * P[0];
  S = (((Cmat[0] + xq) - P[1]) * dOCV - ((Cmat[1] + dOCV * P[2]) - P[3])) +
      prm->R;
  b = V_k - *vhat;
  xq = (xq - P[2]) / S;
  K_idx_0 = xq;
  x[0] += xq * b;
  xq = (P[1] * dOCV - P[3]) / S;
  x[1] += xq * b;
  x[0] = fmin(fmax(x[0], 0.0), 1.0);
  eye(A);
  b_A[0] = A[0] - K_idx_0 * dOCV;
  b_A[1] = A[1] - xq * dOCV;
  b_A[2] = A[2] - (-K_idx_0);
  b_A[3] = A[3] - (-xq);
  memset(&A[0], 0, sizeof(double) << 2);
  xq = b_A[0];
  K_idx_0 = b_A[1];
  dOCV = b_A[2];
  S = b_A[3];
  for (b_i = 0; b_i < 2; b_i++) {
    double d;
    double d1;
    k = b_i << 1;
    b = P[k];
    d = A[k] + xq * b;
    d1 = A[k + 1] + K_idx_0 * b;
    b = P[k + 1];
    d += dOCV * b;
    A[k] = d;
    d1 += S * b;
    A[k + 1] = d1;
  }
  P[0] = A[0];
  P[1] = A[1];
  P[2] = A[2];
  P[3] = A[3];
  *soc = x[0];
  *vrc = x[1];
  /*  --- 时间预测（推进到下一周期）--- */
  xq = x[0];
  K_idx_0 = x[1];
  x[0] = xq - dt / (prm->Cap_Ah * 3600.0) * I_k;
  x[1] = a * K_idx_0 + prm->R1_Ohm * (1.0 - a) * I_k;
  x[0] = fmin(fmax(x[0], 0.0), 1.0);
  memset(&b_A[0], 0, sizeof(double) << 2);
  for (b_i = 0; b_i < 2; b_i++) {
    k = b_i << 1;
    b_A[k] += P[k];
    b_A[k + 1] += a * P[k + 1];
  }
  for (b_i = 0; b_i < 2; b_i++) {
    P[b_i] = b_A[b_i] + prm->Q[b_i];
    P[b_i + 2] = b_A[b_i + 2] * a + prm->Q[b_i + 2];
  }
}

/*
 * Arguments    : void
 * Return Type  : void
 */
void ekf_soc_step_cg_init(void)
{
  x_not_empty = false;
}

/*
 * File trailer for ekf_soc_step_cg.c
 *
 * [EOF]
 */
