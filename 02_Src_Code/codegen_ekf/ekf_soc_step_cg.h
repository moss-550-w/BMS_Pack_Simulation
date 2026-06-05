/*
 * File: ekf_soc_step_cg.h
 *
 * MATLAB Coder version            : 25.1
 * C/C++ source code generated on  : 2026-06-05 15:20:07
 */

#ifndef EKF_SOC_STEP_CG_H
#define EKF_SOC_STEP_CG_H

/* Include Files */
#include "ekf_soc_step_cg_types.h"
#include "rtwtypes.h"
#include <stddef.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Function Declarations */
extern void ekf_soc_step_cg(double I_k, double V_k, double dt,
                            const struct0_T *prm, bool reset, double *soc,
                            double *vrc, double *vhat);

void ekf_soc_step_cg_init(void);

#ifdef __cplusplus
}
#endif

#endif
/*
 * File trailer for ekf_soc_step_cg.h
 *
 * [EOF]
 */
